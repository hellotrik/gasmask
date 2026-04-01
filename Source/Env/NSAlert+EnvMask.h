#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSAlert (EnvMask)

/// LSUIElement / 菜单栏应用里 NSAlert 常落在其它应用后面且抢不到键盘；先激活再抬升窗口后 runModal。
- (NSModalResponse)envmask_runModalRaised;

/// 同上，并在窗口出现后尽量把键盘焦点放到 accessory 里的控件（例如 KEY 输入框）。
- (NSModalResponse)envmask_runModalRaisedWithInitialFirstResponder:(nullable NSView *)view;

@end

NS_ASSUME_NONNULL_END
