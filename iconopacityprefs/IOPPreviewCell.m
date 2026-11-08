#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <Preferences/PSTableCell.h>
#import <Preferences/PSSpecifier.h>
#import "IOPRootListController.h"

NSString *const IOPPreviewNeedsRefresh = @"IOPPreviewNeedsRefresh";

static NSString *const kIOPDomain = @"com.example.iconopacity";

// Системный способ получить иконку приложения (приватный метод UIKit)
@interface UIImage (IOPPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

static double IOPDouble(NSString *key, double def, double lo, double hi) {
    id v = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kIOPDomain);
    double d = [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : def;
    if (d < lo) d = lo;
    if (d > hi) d = hi;
    return d;
}

static BOOL IOPBool(NSString *key, BOOL def) {
    id v = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kIOPDomain);
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : def;
}


// Пытаемся достать обои рабочего стола: сначала готовые миниатюры,
// потом файл .cpbitmap (через системную функцию AppSupport).
typedef CFArrayRef (*IOPCPBitmapFunc)(CFDataRef, void *, int, void *);

static UIImage *IOPWallpaperImage(void) {
    NSString *dir = @"/var/mobile/Library/SpringBoard";

    for (NSString *name in @[@"HomeBackgroundThumbnail.jpg", @"LockBackgroundThumbnail.jpg"]) {
        UIImage *img = [UIImage imageWithContentsOfFile:[dir stringByAppendingPathComponent:name]];
        if (img) return img;
    }

    void *handle = dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_LAZY);
    IOPCPBitmapFunc fn = handle ? (IOPCPBitmapFunc)dlsym(handle, "CPBitmapCreateImagesFromData") : NULL;
    if (!fn) return nil;

    for (NSString *name in @[@"HomeBackground.cpbitmap", @"LockBackground.cpbitmap"]) {
        NSData *data = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:name]];
        if (!data) continue;
        CFArrayRef images = fn((__bridge CFDataRef)data, NULL, 1, NULL);
        if (!images) continue;
        UIImage *result = nil;
        if (CFArrayGetCount(images) > 0) {
            CGImageRef cg = (CGImageRef)CFArrayGetValueAtIndex(images, 0);
            result = [UIImage imageWithCGImage:cg];
        }
        CFRelease(images);
        if (result) return result;
    }
    return nil;
}

// Ячейка-предпросмотр: иконка Safari на цветном фоне, подпись и цветной слой
@interface IOPPreviewCell : PSTableCell
@end

@implementation IOPPreviewCell {
    UIView *_stage;
    CAGradientLayer *_gradient;
    UIImageView *_wallpaperView;
    UIImageView *_iconView;
    UIView *_tintView;
    UILabel *_label;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];

        _stage = [[UIView alloc] init];
        _stage.layer.cornerRadius = 16.0;
        _stage.clipsToBounds = YES;

        // Яркий фон, на котором хорошо видна прозрачность
        _gradient = [CAGradientLayer layer];
        _gradient.colors = @[
            (id)[UIColor colorWithRed:0.20 green:0.42 blue:0.95 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.93 green:0.36 blue:0.58 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:1.00 green:0.74 blue:0.28 alpha:1.0].CGColor
        ];
        _gradient.startPoint = CGPointMake(0.0, 0.0);
        _gradient.endPoint = CGPointMake(1.0, 1.0);
        [_stage.layer addSublayer:_gradient];

        // Настоящие обои рабочего стола (если получилось их прочитать)
        _wallpaperView = [[UIImageView alloc] init];
        _wallpaperView.contentMode = UIViewContentModeScaleAspectFill;
        _wallpaperView.clipsToBounds = YES;
        UIImage *wallpaper = IOPWallpaperImage();
        if (wallpaper) {
            _wallpaperView.image = wallpaper;
        }
        _wallpaperView.hidden = (wallpaper == nil);
        [_stage addSubview:_wallpaperView];

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.clipsToBounds = YES;
        _iconView.layer.cornerRadius = 60.0 * 0.2237;

        UIImage *image = nil;
        if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
            image = [UIImage _applicationIconImageForBundleIdentifier:@"com.apple.mobilesafari"
                                                               format:2
                                                                scale:[UIScreen mainScreen].scale];
        }
        if (image) {
            _iconView.image = image;
        } else {
            // Запасной вариант, если системную иконку получить не удалось
            _iconView.backgroundColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
        }
        [_stage addSubview:_iconView];

        // Цветной слой лежит поверх иконки, как и в самом твике
        _tintView = [[UIView alloc] init];
        _tintView.userInteractionEnabled = NO;
        _tintView.clipsToBounds = YES;
        _tintView.layer.cornerRadius = 60.0 * 0.2237;
        [_stage addSubview:_tintView];

        _label = [[UILabel alloc] init];
        _label.text = @"Safari";
        _label.textColor = [UIColor whiteColor];
        _label.font = [UIFont systemFontOfSize:12.0];
        _label.textAlignment = NSTextAlignmentCenter;
        [_stage addSubview:_label];

        [self.contentView addSubview:_stage];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(refresh)
                                                     name:IOPPreviewNeedsRefresh
                                                   object:nil];
        [self refresh];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.contentView.bounds;
    _stage.frame = CGRectInset(bounds, 16.0, 8.0);
    _gradient.frame = _stage.bounds;
    _wallpaperView.frame = _stage.bounds;

    CGFloat size = 60.0;
    CGFloat contentHeight = size + 6.0 + 16.0;
    CGFloat top = (CGRectGetHeight(_stage.bounds) - contentHeight) / 2.0;
    CGFloat centerX = CGRectGetMidX(_stage.bounds);

    _iconView.frame = CGRectMake(centerX - size / 2.0, top, size, size);
    _tintView.frame = _iconView.frame;
    _label.frame = CGRectMake(centerX - 50.0, top + size + 6.0, 100.0, 16.0);
}

// Читаем сохранённые настройки и применяем их к картинке
- (void)refresh {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kIOPDomain);

    BOOL enabled = IOPBool(@"enabled", YES);
    CGFloat alpha = IOPDouble(@"alpha", 0.8, 0.1, 1.0);
    CGFloat labelAlpha = IOPDouble(@"labelAlpha", 1.0, 0.0, 1.0);
    BOOL tintEnabled = IOPBool(@"tintEnabled", NO);
    CGFloat r = IOPDouble(@"tintRed", 0.0, 0.0, 1.0);
    CGFloat g = IOPDouble(@"tintGreen", 0.0, 0.0, 1.0);
    CGFloat b = IOPDouble(@"tintBlue", 0.0, 0.0, 1.0);
    CGFloat tintAlpha = IOPDouble(@"tintAlpha", 0.3, 0.0, 1.0);

    _iconView.alpha = enabled ? alpha : 1.0;
    _label.alpha = labelAlpha;
    _tintView.hidden = !tintEnabled;
    _tintView.backgroundColor = [UIColor colorWithRed:r green:g blue:b alpha:tintAlpha];
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    [self refresh];
}

@end
