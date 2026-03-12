#import "YTVolumeHUD.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// YouTube Settings Headers
@interface YTSettingsCell : UITableViewCell
@end

@interface YTSettingsSectionItem : NSObject
+ (instancetype)switchItemWithTitle:(NSString *)title
                   titleDescription:(NSString *)titleDescription
            accessibilityIdentifier:(NSString *)accessibilityIdentifier
                           switchOn:(BOOL)switchOn
                        switchBlock:(BOOL (^)(YTSettingsCell *cell,
                                              BOOL enabled))switchBlock
                      settingItemId:(int)settingItemId;
@end

@interface YTSettingsViewController : UIViewController
- (void)setSectionItems:(NSMutableArray<YTSettingsSectionItem *> *)items
            forCategory:(NSUInteger)category
                  title:(NSString *)title
       titleDescription:(NSString *)titleDescription
           headerHidden:(BOOL)headerHidden;
- (void)setSectionItems:(NSMutableArray<YTSettingsSectionItem *> *)items
            forCategory:(NSUInteger)category
                  title:(NSString *)title
                   icon:(id)icon
       titleDescription:(NSString *)titleDescription
           headerHidden:(BOOL)headerHidden;
@end

@interface YTSettingsGroupData : NSObject
@property(nonatomic, assign) NSInteger type;
- (NSArray<NSNumber *> *)orderedCategories;
@end

@interface YTAppSettingsPresentationData : NSObject
+ (NSArray<NSNumber *> *)settingsCategoryOrder;
@end

@interface YTSettingsSectionItemManager : NSObject
- (void)updateVolumeBoostYTSectionWithEntry:(id)entry;
@end

static const NSInteger TweakSection = 'ndyt';
static NSString *const kVolumeBoostYTEnabledKey = @"VolumeBoostYTEnabled";

static BOOL IsVolumeBoostYTEnabled() {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  if ([defaults objectForKey:kVolumeBoostYTEnabledKey] == nil) {
    return YES; // Default to enabled
  }
  return [defaults boolForKey:kVolumeBoostYTEnabledKey];
}

// -----------------------------------------------------
// CONFIGURATION: Set to 1 to remember volume across app restarts, 0 to reset to
// 100% on launch.
// -----------------------------------------------------
#define ENABLE_VOLUME_PERSISTENCE 0

#if ENABLE_VOLUME_PERSISTENCE
static NSString *const kCustomYouTubeVolumeScalarKey =
    @"CustomYouTubeVolumeScalar";
#else
static float currentVolumeMultiplier = 1.0f;
#endif

static NSHashTable *activeRenderers = nil;

static void RegisterRenderer(id renderer) {
  if (!activeRenderers) {
    activeRenderers = [NSHashTable weakObjectsHashTable];
  }
  if (renderer) {
    [activeRenderers addObject:renderer];
  }
}

// Helper to get current volume multiplier
static float GetCustomVolumeMultiplier() {
#if ENABLE_VOLUME_PERSISTENCE
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  if ([defaults objectForKey:kCustomYouTubeVolumeScalarKey] == nil) {
    return 1.0f; // Default to 100% volume
  }
  return [defaults floatForKey:kCustomYouTubeVolumeScalarKey];
#else
  return currentVolumeMultiplier;
#endif
}

static float GetLogarithmicAudioMultiplier() {
  float m = GetCustomVolumeMultiplier();
  if (m <= 1.0f) {
    return m;
  }
  // m goes from 1.0 to 20.0 in the UI (2000%).
  // We map this linearly to an exponent to achieve 200.0x physical amplitude
  // max. powf(200.0f, (m - 1.0f) / 19.0f) ensures m=20 gives 200^1 = 200x.
  return powf(200.0f, (m - 1.0f) / 19.0f);
}

static void NotifyVolumeChange() {
  for (id renderer in [activeRenderers allObjects]) {
    if ([renderer respondsToSelector:@selector(setVolume:)]) {
      // Re-apply base volume 1.0, which then gets intercepted by our hook to
      // apply the multiplier
      [renderer setVolume:1.0f];
    }
  }
}

static void SetCustomVolumeMultiplier(float multiplier) {
  if (multiplier < 0.0f)
    multiplier = 0.0f;
  if (multiplier > 20.0f)
    multiplier = 20.0f;

#if ENABLE_VOLUME_PERSISTENCE
  [[NSUserDefaults standardUserDefaults]
      setFloat:multiplier
        forKey:kCustomYouTubeVolumeScalarKey];
  [[NSUserDefaults standardUserDefaults] synchronize];
#else
  currentVolumeMultiplier = multiplier;
#endif

  NotifyVolumeChange();
}

// -----------------------------------------------------
// High level AVFoundation / MediaPlayer Hooks
// -----------------------------------------------------

%hook AVPlayer
- (instancetype)init {
  id orig = %orig;
  RegisterRenderer(orig);
  return orig;
}
- (void)setVolume:(float)volume {
  RegisterRenderer(self);
  if (IsVolumeBoostYTEnabled()) {
    volume = volume * GetLogarithmicAudioMultiplier();
  }
  %orig(volume);
}
%end

%hook AVAudioPlayerNode
- (instancetype)init {
  id orig = %orig;
  RegisterRenderer(orig);
  return orig;
}
- (void)setVolume:(float)volume {
  RegisterRenderer(self);
  if (IsVolumeBoostYTEnabled()) {
    volume = volume * GetLogarithmicAudioMultiplier();
  }
  %orig(volume);
}
%end

%hook AVAudioPlayer
- (instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)outError {
  id orig = %orig;
  RegisterRenderer(orig);
  return orig;
}
- (instancetype)initWithData:(NSData *)data error:(NSError **)outError {
  id orig = %orig;
  RegisterRenderer(orig);
  return orig;
}
- (void)setVolume:(float)volume {
  RegisterRenderer(self);
  if (IsVolumeBoostYTEnabled()) {
    volume = volume * GetLogarithmicAudioMultiplier();
  }
  %orig(volume);
}
%end

%hook AVSampleBufferAudioRenderer
- (instancetype)init {
  id orig = %orig;
  RegisterRenderer(orig);
  return orig;
}
- (void)setVolume:(float)volume {
  RegisterRenderer(self);
  if (IsVolumeBoostYTEnabled()) {
    volume = volume * GetLogarithmicAudioMultiplier();
  }
  %orig(volume);
}
%end

    // -----------------------------------------------------
    // UI Hooks for Configuration (Native Touch Tracking via sendEvent:)
    // -----------------------------------------------------

    static float gestureStartMultiplier = 1.0f;
static BOOL possibleVolumeGesture = NO;
static BOOL isTrackingVolumeGesture = NO;
static CGPoint initialTouchPoint;

%hook UIWindow
- (void)sendEvent:(UIEvent *)event {
  // Escape early if tweak is globally disabled in YouTube settings
  if (!IsVolumeBoostYTEnabled()) {
    %orig(event);
    return;
  }

  // Only track touches from the main screen
  if (self.screen != [UIScreen mainScreen]) {
    %orig(event);
    return;
  }

  NSSet<UITouch *> *touches = [event allTouches];
  if (touches.count == 0) {
    %orig(event);
    return;
  }

  UITouch *touch = [touches anyObject];
  CGPoint location = [touch locationInView:self];

  switch (touch.phase) {
  case UITouchPhaseBegan: {
    // Check if the touch is within 25 points of the right edge
    CGFloat screenWidth = self.bounds.size.width;
    if (location.x >= screenWidth - 25.0f) {
      possibleVolumeGesture = YES;
      isTrackingVolumeGesture = NO;
      initialTouchPoint = location;
      return; // Swallow the touch, start evaluating gesture
    }
    break;
  }
  case UITouchPhaseMoved: {
    if (possibleVolumeGesture) {
      CGFloat dx = initialTouchPoint.x - location.x; // Positive if moving left
      CGFloat dy = fabs(location.y - initialTouchPoint.y);

      // Require moving left (inwards) by at least 15 points before locking in
      if (dx > 15.0f && dx > dy) {
        isTrackingVolumeGesture = YES;
        possibleVolumeGesture = NO;

        // Lock in! Now calculate relative vertical drag from this exact point
        initialTouchPoint = location;
        gestureStartMultiplier = GetCustomVolumeMultiplier();
        [[YTVolumeHUD sharedHUD] showWithValue:gestureStartMultiplier];
        return; // Swallow
      } else if (dy > 20.0f || dx < -10.0f) {
        // Failed gesture (moved up/down too early, or moved further right off
        // screen)
        possibleVolumeGesture = NO;
      } else {
        return; // Still evaluating, swallow touch
      }
    }

    if (isTrackingVolumeGesture) {
      CGFloat translationY = location.y - initialTouchPoint.y;

      // Sweeping vertically up (negative Y) increases volume
      // A full 570-point swipe upward reaches the 20x multiplier
      float deltaMultiplier = -translationY / 30.0f;
      float newMultiplier = gestureStartMultiplier + deltaMultiplier;

      if (newMultiplier < 0.0f)
        newMultiplier = 0.0f;
      if (newMultiplier > 20.0f)
        newMultiplier = 20.0f;

      SetCustomVolumeMultiplier(newMultiplier);
      [[YTVolumeHUD sharedHUD] showWithValue:newMultiplier];
      return; // Swallow the touch
    }
    break;
  }
  case UITouchPhaseEnded:
  case UITouchPhaseCancelled: {
    if (possibleVolumeGesture) {
      possibleVolumeGesture = NO;
      return; // Swallowed aborted tap
    }
    if (isTrackingVolumeGesture) {
      isTrackingVolumeGesture = NO;
      [[YTVolumeHUD sharedHUD] performSelector:@selector(hide)
                                    withObject:nil
                                    afterDelay:1.0];
      return; // Swallow the touch
    }
    break;
  }
  default:
    break;
  }

  // Pass the event to the app if we are not tracking our custom gesture
  %orig(event);
}
%end

        // -----------------------------------------------------
        // YouTube In-App Settings Integration
        // -----------------------------------------------------

        %group YouTubeSettings

        %hook YTSettingsGroupData

    - (NSArray<NSNumber *> *)orderedCategories {
  // Only inject into the main settings group (type 1)
  if (self.type != 1)
    return %orig;

  // If another tweak (YouGroupSettings) handles grouping, let it do so
  if (class_getClassMethod(objc_getClass("YTSettingsGroupData"),
                           @selector(tweaks))) {
    return %orig;
  }

  NSMutableArray *mutableCategories = %orig.mutableCopy;
  if (mutableCategories) {
    // Insert our tweak section near the top
    [mutableCategories insertObject:@(TweakSection) atIndex:0];
  }
  return mutableCategories.copy ?: %orig;
}

+ (NSMutableArray<NSNumber *> *)tweaks {
  NSMutableArray<NSNumber *> *tweaks = %orig;
  if (tweaks && ![tweaks containsObject:@(TweakSection)]) {
    [tweaks addObject:@(TweakSection)];
  }
  return tweaks;
}

%end

        %hook YTAppSettingsPresentationData

    + (NSArray<NSNumber *> *)settingsCategoryOrder {
  NSArray<NSNumber *> *order = %orig;
  NSUInteger insertIndex = [order indexOfObject:@(1)];

  if (insertIndex != NSNotFound) {
    NSMutableArray<NSNumber *> *mutableOrder = [order mutableCopy];
    [mutableOrder insertObject:@(TweakSection) atIndex:insertIndex + 1];
    return mutableOrder.copy;
  }

  return order ?: %orig;
}

%end

        %hook YTSettingsSectionItemManager

        %new(v@:@)
    - (void)updateVolumeBoostYTSectionWithEntry:(id)entry {
  NSMutableArray<YTSettingsSectionItem *> *sectionItems =
      [NSMutableArray array];
  Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);

  // Fallback if class not available (though it should be)
  if (!YTSettingsSectionItemClass)
    return;

  YTSettingsViewController *settingsViewController =
      [self valueForKey:@"_settingsViewControllerDelegate"];

  YTSettingsSectionItem *enableTweak = [YTSettingsSectionItemClass
          switchItemWithTitle:@"Enable VolumeBoostYT"
             titleDescription:@"Allow custom right-edge pan volume gesture"
      accessibilityIdentifier:nil
                     switchOn:IsVolumeBoostYTEnabled()
                  switchBlock:^BOOL(YTSettingsCell *cell, BOOL enabled) {
                    [[NSUserDefaults standardUserDefaults]
                        setBool:enabled
                         forKey:kVolumeBoostYTEnabledKey];
                    [[NSUserDefaults standardUserDefaults] synchronize];

                    // Re-fire volume to normalize or amplify existing active
                    // players immediately
                    if (!enabled) {
                      SetCustomVolumeMultiplier(1.0f);
                    }
                    NotifyVolumeChange();
                    return YES;
                  }
                settingItemId:0];
  [sectionItems addObject:enableTweak];

  if ([settingsViewController
          respondsToSelector:@selector
          (setSectionItems:
               forCategory:title:icon:titleDescription:headerHidden:)]) {
    [settingsViewController setSectionItems:sectionItems
                                forCategory:TweakSection
                                      title:@"VolumeBoostYT"
                                       icon:nil
                           titleDescription:nil
                               headerHidden:NO];
  } else if ([settingsViewController
                 respondsToSelector:@selector
                 (setSectionItems:
                      forCategory:title:titleDescription:headerHidden:)]) {
    [settingsViewController setSectionItems:sectionItems
                                forCategory:TweakSection
                                      title:@"VolumeBoostYT"
                           titleDescription:nil
                               headerHidden:NO];
  }
}

- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
  if (category == TweakSection) {
    [self updateVolumeBoostYTSectionWithEntry:entry];
    return;
  }
  %orig;
}

%end

    %end // end group YouTubeSettings

    %ctor {
  // Check if YouTube classes exist instead of relying on Bundle ID,
  // because sideloaded apps (like LiveContainer) often change their Bundle IDs.
  if (NSClassFromString(@"YTSettingsGroupData")) {
    %init(YouTubeSettings);
  }

  // Always initialize the core AVPlayer and UIWindow touch hooks for every app
  %init;
}
