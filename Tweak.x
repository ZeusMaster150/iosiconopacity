#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Настройки лежат в /var/mobile/Library/Preferences/com.example.iconopacity.plist
static NSString *const kDomain = @"com.example.iconopacity";
static NSString *const kReloadNotification = @"com.example.iconopacity/ReloadPrefs";
static const NSInteger kTintTag = 0x1C0A;

// Прозрачность иконок
static BOOL gEnabled = YES;
static CGFloat gAlpha = 0.8;

// Прозрачность подписей под иконками (1.0 = как обычно)
static CGFloat gLabelAlpha = 1.0;
static const void *kLabelTouchedKey = &kLabelTouchedKey;

// Цветной слой поверх иконок
static BOOL gTintEnabled = NO;
static CGFloat gTintR = 0.0, gTintG = 0.0, gTintB = 0.0;
static CGFloat gTintAlpha = 0.3;

static NSHashTable *gViews; // слабые ссылки на иконки, чтобы менять их сразу

@interface SBIconView : UIView
@end

// Достаём картинку иконки (без подписи) из SBIconView.
static UIView *IconImageViewFor(UIView *iconView) {
    @try {
        id v = [iconView valueForKey:@"iconImageView"];
        if ([v isKindOfClass:[UIView class]]) return v;
    } @catch (NSException *e) {
    }
    return nil;
}

// Цветной слой лежит рядом с картинкой иконки (а не внутри),
// поэтому его прозрачность не зависит от прозрачности иконки.
static void ApplyTint(UIView *img) {
    UIView *host = img.superview;
    if (!host) return;

    UIView *overlay = nil;
    for (UIView *sub in host.subviews) {
        if (sub.tag == kTintTag) {
            overlay = sub;
            break;
        }
    }

    if (!gTintEnabled) {
        overlay.hidden = YES;
        return;
    }

    if (!overlay) {
        overlay = [[UIView alloc] init];
        overlay.tag = kTintTag;
        overlay.userInteractionEnabled = NO;
        overlay.clipsToBounds = YES;
        [host insertSubview:overlay aboveSubview:img];
    }

    overlay.hidden = NO;
    overlay.frame = img.frame;
    overlay.layer.cornerRadius = MIN(img.bounds.size.width, img.bounds.size.height) * 0.2237;
    overlay.backgroundColor = [UIColor colorWithRed:gTintR green:gTintG blue:gTintB alpha:gTintAlpha];
}

// Подпись под иконкой (SBIconView хранит её как labelView)
static UIView *LabelViewFor(UIView *iconView) {
    @try {
        id v = [iconView valueForKey:@"labelView"];
        if ([v isKindOfClass:[UIView class]]) return v;
    } @catch (NSException *e) {
    }
    return nil;
}

static void ApplyLabel(UIView *iconView) {
    UIView *label = LabelViewFor(iconView);
    if (!label || label.hidden) return;

    BOOL touched = [objc_getAssociatedObject(label, kLabelTouchedKey) boolValue];
    // Пока подписи не трогали и значение 1.0, ничего не делаем
    if (gLabelAlpha > 0.999 && !touched) return;
    // Если систему скрыла подпись сама (alpha почти 0), не возвращаем её
    if (!touched && label.alpha < 0.01) return;

    if (label.alpha != gLabelAlpha) {
        label.alpha = gLabelAlpha;
    }
    objc_setAssociatedObject(label, kLabelTouchedKey,
                             (gLabelAlpha > 0.999) ? nil : @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void ApplyToIconView(UIView *iconView) {
    UIView *img = IconImageViewFor(iconView);
    if (!img) return;

    CGFloat target = gEnabled ? gAlpha : 1.0;
    if (img.alpha != target) {
        img.alpha = target;
    }
    ApplyTint(img);
    ApplyLabel(iconView);
}

static double PrefDouble(NSString *key, double def, double lo, double hi) {
    id v = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kDomain);
    double d = [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : def;
    if (d < lo) d = lo;
    if (d > hi) d = hi;
    return d;
}

static BOOL PrefBool(NSString *key, BOOL def) {
    id v = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kDomain);
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : def;
}

static void LoadPrefs(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
    gEnabled = PrefBool(@"enabled", YES);
    gAlpha = PrefDouble(@"alpha", 0.8, 0.1, 1.0);
    gLabelAlpha = PrefDouble(@"labelAlpha", 1.0, 0.0, 1.0);
    gTintEnabled = PrefBool(@"tintEnabled", NO);
    gTintR = PrefDouble(@"tintRed", 0.0, 0.0, 1.0);
    gTintG = PrefDouble(@"tintGreen", 0.0, 0.0, 1.0);
    gTintB = PrefDouble(@"tintBlue", 0.0, 0.0, 1.0);
    gTintAlpha = PrefDouble(@"tintAlpha", 0.3, 0.0, 1.0);
}

// Вызывается, когда в Настройках двигают ползунок
static void ReloadPrefs(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    LoadPrefs();
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIView *v in gViews.allObjects) {
            ApplyToIconView(v);
        }
    });
}

%hook SBIconView
- (void)layoutSubviews {
    %orig;
    if (!gViews) {
        gViews = [NSHashTable weakObjectsHashTable];
    }
    [gViews addObject:self];
    ApplyToIconView(self);
}
%end

%ctor {
    LoadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    (CFNotificationCallback)ReloadPrefs,
                                    (__bridge CFStringRef)kReloadNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorCoalesce);
}
