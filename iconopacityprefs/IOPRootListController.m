#import "IOPRootListController.h"

@implementation IOPRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

// Каждый раз, когда двигают ползунок или переключатель,
// просим окно предпросмотра перерисоваться.
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    [[NSNotificationCenter defaultCenter] postNotificationName:IOPPreviewNeedsRefresh object:nil];
}

@end
