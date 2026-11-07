#import <UIKit/UIKit.h>

// Файл настроек: в нём одна строка alpha (число от 0.1 до 1.0)
static NSString *const kPrefsPath = @"/var/mobile/Library/Preferences/com.example.iconopacity.plist";
static CGFloat gAlpha = 0.8;

@interface SBIconView : UIView
@end

// Достаём картинку иконки (без подписи) из SBIconView.
// valueForKey сам найдёт метод iconImageView или переменную _iconImageView.
static UIView *IconImageViewFor(UIView *iconView) {
    @try {
        id v = [iconView valueForKey:@"iconImageView"];
        if ([v isKindOfClass:[UIView class]]) return v;
    } @catch (NSException *e) {
    }
    return nil;
}

%hook SBIconView
- (void)layoutSubviews {
    %orig;
    UIView *img = IconImageViewFor(self);
    if (img && img.alpha != gAlpha) {
        img.alpha = gAlpha;
    }
}
%end

%ctor {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
    id value = prefs[@"alpha"];
    if ([value respondsToSelector:@selector(doubleValue)]) {
        CGFloat a = [value doubleValue];
        if (a < 0.1) a = 0.1;
        if (a > 1.0) a = 1.0;
        gAlpha = a;
    }
}
