#import "YTVolumeHUD.h"
#import <UIKit/UIKit.h>

@implementation YTVolumeHUD

+ (instancetype)sharedHUD {
  static YTVolumeHUD *sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[self alloc] init];
  });
  return sharedInstance;
}

- (instancetype)init {
  self = [super initWithFrame:CGRectMake(0, 0, 200, 40)];
  if (self) {
    self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.8];
    self.layer.cornerRadius = 20;
    self.clipsToBounds = YES;
    self.userInteractionEnabled = NO;
    self.alpha = 0.0;

    self.textLabel = [[UILabel alloc] initWithFrame:self.bounds];
    self.textLabel.textColor = [UIColor whiteColor];
    self.textLabel.textAlignment = NSTextAlignmentCenter;
    self.textLabel.font = [UIFont boldSystemFontOfSize:16];
    [self addSubview:self.textLabel];
  }
  return self;
}

- (void)showWithValue:(float)value {
  self.textLabel.text =
      [NSString stringWithFormat:@"App Vol: %.0f%%", value * 100];

  UIWindow *window = nil;
  if (@available(iOS 13.0, *)) {
    for (UIWindowScene *scene in [UIApplication sharedApplication]
             .connectedScenes) {
      if (scene.activationState == UISceneActivationStateForegroundActive) {
        for (UIWindow *w in scene.windows) {
          if (w.isKeyWindow) {
            window = w;
            break;
          }
        }
        if (window)
          break;
      }
    }
  } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    window = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
  }

  if (!window)
    return;

  if (self.superview != window) {
    [window addSubview:self];
  }

  // Center it near the top of the screen below the status bar
  self.center = CGPointMake(window.bounds.size.width / 2.0, 80);
  [window bringSubviewToFront:self];

  [UIView animateWithDuration:0.2
                   animations:^{
                     self.alpha = 1.0;
                   }];

  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(hide)
                                             object:nil];
  [self performSelector:@selector(hide) withObject:nil afterDelay:1.5];
}

- (void)hide {
  [UIView animateWithDuration:0.3
      animations:^{
        self.alpha = 0.0;
      }
      completion:^(BOOL finished) {
        if (finished) {
          [self removeFromSuperview];
        }
      }];
}

@end
