/***************************************************************************
 * Minimal arm64 stand-in for ShortcutRecorder.framework (x86_64/i386 only).
 * Lets Preferences.xib load; hotkey recording UI is non-functional.
 ***************************************************************************/

#import <ShortcutRecorder/SRRecorderControl.h>
#import <ShortcutRecorder/SRRecorderCell.h>
#import <Carbon/Carbon.h>

NSUInteger SRCarbonToCocoaFlags(NSUInteger carbonFlags)
{
	NSUInteger cocoa = 0;
	if (carbonFlags & cmdKey) cocoa |= NSEventModifierFlagCommand;
	if (carbonFlags & optionKey) cocoa |= NSEventModifierFlagOption;
	if (carbonFlags & shiftKey) cocoa |= NSEventModifierFlagShift;
	if (carbonFlags & controlKey) cocoa |= NSEventModifierFlagControl;
	return cocoa;
}

NSUInteger SRCocoaToCarbonFlags(NSUInteger cocoaFlags)
{
	NSUInteger carbon = 0;
	if (cocoaFlags & NSEventModifierFlagCommand) carbon |= cmdKey;
	if (cocoaFlags & NSEventModifierFlagOption) carbon |= optionKey;
	if (cocoaFlags & NSEventModifierFlagShift) carbon |= shiftKey;
	if (cocoaFlags & NSEventModifierFlagControl) carbon |= controlKey;
	return carbon;
}

CGFloat SRAnimationEaseInOut(CGFloat t)
{
	return t;
}

@implementation SRDummyClass
@end

@implementation SRRecorderCell
@end

@implementation SRRecorderControl
{
	KeyCombo _keyCombo;
	id _delegate;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self) {
		_keyCombo.code = -1;
		_keyCombo.flags = 0;
	}
	return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
	self = [super initWithCoder:coder];
	if (self) {
		_keyCombo.code = -1;
		_keyCombo.flags = 0;
	}
	return self;
}

- (BOOL)animates { return NO; }
- (void)setAnimates:(BOOL)an {}
- (SRRecorderStyle)style { return SRGradientBorderStyle; }
- (void)setStyle:(SRRecorderStyle)nStyle {}

- (id)delegate { return _delegate; }
- (void)setDelegate:(id)aDelegate { _delegate = aDelegate; }

- (NSUInteger)allowedFlags { return NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagShift | NSEventModifierFlagControl; }
- (void)setAllowedFlags:(NSUInteger)flags {}

- (BOOL)allowsKeyOnly { return NO; }
- (void)setAllowsKeyOnly:(BOOL)nAllowsKeyOnly escapeKeysRecord:(BOOL)nEscapeKeysRecord {}
- (BOOL)escapeKeysRecord { return NO; }

- (BOOL)canCaptureGlobalHotKeys { return NO; }
- (void)setCanCaptureGlobalHotKeys:(BOOL)inState {}

- (NSUInteger)requiredFlags { return 0; }
- (void)setRequiredFlags:(NSUInteger)flags {}

- (KeyCombo)keyCombo { return _keyCombo; }
- (void)setKeyCombo:(KeyCombo)aKeyCombo { _keyCombo = aKeyCombo; [self setNeedsDisplay:YES]; }

- (NSString *)keyChars { return @""; }
- (NSString *)keyCharsIgnoringModifiers { return @""; }

- (NSString *)autosaveName { return nil; }
- (void)setAutosaveName:(NSString *)aName {}

- (NSString *)keyComboString { return @"(unavailable on arm64)"; }

- (NSUInteger)cocoaToCarbonFlags:(NSUInteger)cocoaFlags { return SRCocoaToCarbonFlags(cocoaFlags); }
- (NSUInteger)carbonToCocoaFlags:(NSUInteger)carbonFlags { return SRCarbonToCocoaFlags(carbonFlags); }

- (NSDictionary *)objectValue { return @{}; }
- (void)setObjectValue:(NSDictionary *)shortcut {}

- (void)drawRect:(NSRect)dirtyRect
{
	[[NSColor controlBackgroundColor] setFill];
	NSRectFill(self.bounds);
	NSString *label = @"Hotkeys unavailable (arm64)";
	NSDictionary *attrs = @{ NSFontAttributeName: [NSFont systemFontOfSize:11] };
	[label drawInRect:NSInsetRect(self.bounds, 4, 2) withAttributes:attrs];
}

@end

@implementation NSAlert (SRAdditions)
+ (NSAlert *)alertWithNonRecoverableError:(NSError *)error
{
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:error.localizedDescription ?: @"Error"];
	return alert;
}
@end

@implementation SRSharedImageProvider
+ (NSImage *)supportingImageWithName:(NSString *)name
{
	return [NSImage imageNamed:name];
}
@end
