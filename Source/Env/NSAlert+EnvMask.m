#import "NSAlert+EnvMask.h"

@implementation NSAlert (EnvMask)

- (void)envmask_raiseAlertWindow
{
	NSWindow *w = self.window;
	if (!w) return;
	[w setLevel:NSPopUpMenuWindowLevel];
	[w setCollectionBehavior:(NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary)];
	[w orderFrontRegardless];
	[w makeKeyWindow];
}

- (void)envmask_scheduleRaiseAndFocus:(NSView *)view
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[self envmask_raiseAlertWindow];
		if (view) {
			NSWindow *w = self.window;
			if (w) [w makeFirstResponder:view];
		}
	});
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self envmask_raiseAlertWindow];
		if (view) {
			NSWindow *w = self.window;
			if (w) [w makeFirstResponder:view];
		}
	});
}

- (NSModalResponse)envmask_runModalRaised
{
	[NSApp activateIgnoringOtherApps:YES];
	[self envmask_scheduleRaiseAndFocus:nil];
	return [self runModal];
}

- (NSModalResponse)envmask_runModalRaisedWithInitialFirstResponder:(NSView *)view
{
	[NSApp activateIgnoringOtherApps:YES];
	[self envmask_scheduleRaiseAndFocus:view];
	return [self runModal];
}

@end
