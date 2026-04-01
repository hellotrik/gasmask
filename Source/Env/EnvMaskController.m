/***************************************************************************
 * EnvMaskController implementation
 ***************************************************************************/

#import "EnvMaskController.h"

#import <AppKit/AppKit.h>

#import "EnvStore.h"
#import "EnvResolver.h"
#import "EnvExporter.h"
#import "NSAlert+EnvMask.h"

@implementation EnvMaskController

static EnvMaskController *sharedInstance = nil;

+ (EnvMaskController *)defaultInstance
{
	if (!sharedInstance) {
		sharedInstance = [EnvMaskController new];
		// Best-effort: keep active.zsh present for shell-only usage.
		NSArray<EnvLayer *> *layers = [[EnvStore defaultInstance] loadLayers];
		NSDictionary *env = [EnvResolver resolveFromLayers:layers];
		[EnvExporter writeActiveZshFromEnv:env error:NULL];
	}
	return sharedInstance;
}

- (void)activateAppAndRunOnMainAsync:(dispatch_block_t)block
{
	// Status bar menu actions run during menu tracking; showing windows/alerts synchronously
	// can lead to "opens but can't type" (key window/focus issues). Activate and defer.
	dispatch_async(dispatch_get_main_queue(), ^{
		[NSApp activateIgnoringOtherApps:YES];
		if (block) block();
	});
}

- (NSString *)subtitleFromEnabledLayers:(NSArray<EnvLayer *> *)layers
{
	NSArray<EnvLayer *> *enabled = [EnvResolver enabledLayersSorted:layers];
	NSMutableArray *names = [NSMutableArray array];
	for (EnvLayer *l in enabled) {
		if (l.name) [names addObject:l.name];
	}
	if ([names count] == 0) return @"(无启用层)";
	return [names componentsJoinedByString:@" + "];
}

- (NSMenu *)createLayersMenu:(NSArray<EnvLayer *> *)layers
{
	NSMenu *menu = [NSMenu new];
	// Keep status bar menus deterministic; avoid AppKit auto-disabling due to responder chain.
	[menu setAutoenablesItems:NO];

	NSArray<EnvLayer *> *sorted = [layers sortedArrayUsingComparator:^NSComparisonResult(EnvLayer *a, EnvLayer *b) {
		if (a.priority < b.priority) return NSOrderedAscending;
		if (a.priority > b.priority) return NSOrderedDescending;
		return [a.name compare:b.name options:NSCaseInsensitiveSearch];
	}];

	for (EnvLayer *l in sorted) {
		NSString *title = [NSString stringWithFormat:@"%@  (prio %ld)", l.name, (long)l.priority];
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(toggleLayerFromMenuItem:) keyEquivalent:@""];
		[item setTarget:self];
		[item setState:(l.enabled ? NSOnState : NSOffState)];
		[item setRepresentedObject:l.layerId];
		[menu addItem:item];
	}

	return menu;
}

- (EnvLayer *)layerById:(NSString *)layerId from:(NSArray<EnvLayer *> *)layers
{
	for (EnvLayer *l in layers) {
		if ([l.layerId isEqualToString:layerId]) return l;
	}
	return nil;
}

- (NSMenu *)createProfilesMenuFromLayers:(NSArray<EnvLayer *> *)layers
{
	// Profiles = layers excluding base/system plumbing if desired; keep base visible but disabled.
	NSMenu *menu = [NSMenu new];
	[menu setAutoenablesItems:NO];

	NSArray<EnvLayer *> *sorted = [layers sortedArrayUsingComparator:^NSComparisonResult(EnvLayer *a, EnvLayer *b) {
		if (a.priority < b.priority) return NSOrderedAscending;
		if (a.priority > b.priority) return NSOrderedDescending;
		return [a.name compare:b.name options:NSCaseInsensitiveSearch];
	}];

	for (EnvLayer *l in sorted) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:l.name action:@selector(toggleLayerFromMenuItem:) keyEquivalent:@""];
		[item setTarget:self];
		[item setRepresentedObject:l.layerId];
		[item setState:(l.enabled ? NSOnState : NSOffState)];

		// Base is always-on in our defaults; make it non-toggle to reduce confusion.
		if ([l.layerId isEqualToString:@"base"]) {
			[item setEnabled:NO];
			[item setState:NSOnState];
		}

		[menu addItem:item];
	}

	return menu;
}

- (NSMenu *)createTempMenuFromLayers:(NSArray<EnvLayer *> *)layers
{
	NSMenu *menu = [NSMenu new];
	[menu setAutoenablesItems:NO];

	EnvLayer *temp = [self layerById:@"temp" from:layers];
	NSString *stateLine = @"Temp: 未启用";
	if (temp && temp.enabled) {
		stateLine = [NSString stringWithFormat:@"Temp: 已启用（%lu项）", (unsigned long)[temp.ops count]];
	} else if (temp) {
		stateLine = [NSString stringWithFormat:@"Temp: 未启用（%lu项）", (unsigned long)[temp.ops count]];
	}

	NSMenuItem *stateItem = [[NSMenuItem alloc] initWithTitle:stateLine action:NULL keyEquivalent:@""];
	[stateItem setEnabled:NO];
	[menu addItem:stateItem];
	[menu addItem:[NSMenuItem separatorItem]];

	NSMenuItem *clearItem = [[NSMenuItem alloc] initWithTitle:@"清空 Temp" action:@selector(clearTempVariables:) keyEquivalent:@""];
	[clearItem setTarget:self];
	[menu addItem:clearItem];

	return menu;
}

- (void)addProfilesItemsToRootMenu:(NSMenu *)root layers:(NSArray<EnvLayer *> *)layers
{
	NSMenuItem *header = [[NSMenuItem alloc] initWithTitle:@"Profiles(配置包开关)" action:NULL keyEquivalent:@""];
	[header setEnabled:NO];
	[root addItem:header];

	NSArray<EnvLayer *> *sorted = [layers sortedArrayUsingComparator:^NSComparisonResult(EnvLayer *a, EnvLayer *b) {
		if (a.priority < b.priority) return NSOrderedAscending;
		if (a.priority > b.priority) return NSOrderedDescending;
		return [a.name compare:b.name options:NSCaseInsensitiveSearch];
	}];

	for (EnvLayer *l in sorted) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:l.name action:@selector(toggleLayerFromMenuItem:) keyEquivalent:@""];
		[item setTarget:self];
		[item setRepresentedObject:l.layerId];
		[item setState:(l.enabled ? NSOnState : NSOffState)];
		[item setIndentationLevel:1];

		// Base is always-on in our defaults; make it non-toggle to reduce confusion.
		if ([l.layerId isEqualToString:@"base"]) {
			[item setEnabled:NO];
			[item setState:NSOnState];
		}

		[root addItem:item];
	}
}

- (void)addTempItemsToRootMenu:(NSMenu *)root layers:(NSArray<EnvLayer *> *)layers
{
	NSMenuItem *header = [[NSMenuItem alloc] initWithTitle:@"Temp(临时变量)" action:NULL keyEquivalent:@""];
	[header setEnabled:NO];
	[root addItem:header];

	EnvLayer *temp = [self layerById:@"temp" from:layers];
	NSString *stateLine = @"Temp: 未启用";
	if (temp && temp.enabled) {
		stateLine = [NSString stringWithFormat:@"Temp: 已启用（%lu项）", (unsigned long)[temp.ops count]];
	} else if (temp) {
		stateLine = [NSString stringWithFormat:@"Temp: 未启用（%lu项）", (unsigned long)[temp.ops count]];
	}

	NSMenuItem *stateItem = [[NSMenuItem alloc] initWithTitle:stateLine action:NULL keyEquivalent:@""];
	[stateItem setEnabled:NO];
	[stateItem setIndentationLevel:1];
	[root addItem:stateItem];

	NSMenuItem *clearItem = [[NSMenuItem alloc] initWithTitle:@"清空 Temp" action:@selector(clearTempVariables:) keyEquivalent:@""];
	[clearItem setTarget:self];
	[clearItem setIndentationLevel:1];
	[root addItem:clearItem];
}

- (BOOL)exportActiveZshWithAlertOnError
{
	NSArray<EnvLayer *> *layers = [[EnvStore defaultInstance] loadLayers];
	NSDictionary *env = [EnvResolver resolveFromLayers:layers];
	NSError *err = nil;
	BOOL ok = [EnvExporter writeActiveZshFromEnv:env error:&err];
	if (!ok) {
		[self activateAppAndRunOnMainAsync:^{
			NSAlert *alert = [NSAlert new];
			[alert setMessageText:@"导出 active.zsh 失败"];
			[alert setInformativeText:(err.localizedDescription ?: @"未知错误")];
			[alert envmask_runModalRaised];
		}];
	}
	return ok;
}

- (NSMenu *)createEnvMaskSubmenu
{
	NSArray<EnvLayer *> *layers = [[EnvStore defaultInstance] ensureTempLayerExists];

	NSMenu *root = [NSMenu new];
	[root setAutoenablesItems:NO];

	// First-time guidance: show current enabled profiles and the shell source line
	NSMenuItem *subtitle = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"当前启用: %@", [self subtitleFromEnabledLayers:layers]]
													  action:NULL
											   keyEquivalent:@""];
	[subtitle setEnabled:NO];
	[root addItem:subtitle];
	BOOL installed = [EnvExporter isZshrcInstalled];
	NSString *hintText = installed ? @"终端自动生效: 已开启（新终端会话生效）" : @"终端自动生效: 未开启";
	NSMenuItem *hint = [[NSMenuItem alloc] initWithTitle:hintText action:NULL keyEquivalent:@""];
	[hint setEnabled:NO];
	[root addItem:hint];

	NSMenuItem *installItem = nil;
	if (installed) {
		installItem = [[NSMenuItem alloc] initWithTitle:@"关闭终端自动生效(从 ~/.zshrc 移除)" action:@selector(uninstallTerminalAutoApply:) keyEquivalent:@""];
	} else {
		installItem = [[NSMenuItem alloc] initWithTitle:@"开启终端自动生效(写入 ~/.zshrc)" action:@selector(installTerminalAutoApply:) keyEquivalent:@""];
	}
	[installItem setTarget:self];
	[root addItem:installItem];
	[root addItem:[NSMenuItem separatorItem]];

	[self addProfilesItemsToRootMenu:root layers:layers];
	[root addItem:[NSMenuItem separatorItem]];
	[self addTempItemsToRootMenu:root layers:layers];

	[root addItem:[NSMenuItem separatorItem]];

	NSMenuItem *exportItem = [[NSMenuItem alloc] initWithTitle:@"立即生成终端环境(刷新)" action:@selector(exportActiveZsh:) keyEquivalent:@""];
	[exportItem setTarget:self];
	[root addItem:exportItem];

	NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"复制终端手动生效命令" action:@selector(copySourceCommand:) keyEquivalent:@""];
	[copyItem setTarget:self];
	[root addItem:copyItem];

	NSMenuItem *openItem = [[NSMenuItem alloc] initWithTitle:@"打开导出的脚本文件" action:@selector(openActiveZsh:) keyEquivalent:@""];
	[openItem setTarget:self];
	[root addItem:openItem];

	return root;
}

- (void)toggleLayerFromMenuItem:(id)sender
{
	NSString *layerId = (NSString *)[sender representedObject];
	if ([layerId length] == 0) return;
	[[EnvStore defaultInstance] toggleLayerEnabledById:layerId];
	[self exportActiveZshWithAlertOnError];
}

- (void)clearTempVariables:(id)sender
{
	[[EnvStore defaultInstance] clearTempLayerOps];
	[self exportActiveZshWithAlertOnError];
}

- (void)installTerminalAutoApply:(id)sender
{
	[self activateAppAndRunOnMainAsync:^{
		NSError *err = nil;
		[self exportActiveZshWithAlertOnError];
		BOOL ok = [EnvExporter installToZshrc:&err];
		if (!ok) {
			NSAlert *a = [NSAlert new];
			[a setMessageText:@"开启失败"];
			[a setInformativeText:(err.localizedDescription ?: @"无法写入 ~/.zshrc")];
			[a envmask_runModalRaised];
		}
	}];
}

- (void)uninstallTerminalAutoApply:(id)sender
{
	[self activateAppAndRunOnMainAsync:^{
		NSError *err = nil;
		BOOL ok = [EnvExporter uninstallFromZshrc:&err];
		if (!ok) {
			NSAlert *a = [NSAlert new];
			[a setMessageText:@"关闭失败"];
			[a setInformativeText:(err.localizedDescription ?: @"无法修改 ~/.zshrc")];
			[a envmask_runModalRaised];
		}
	}];
}

- (void)exportActiveZsh:(id)sender
{
	[self exportActiveZshWithAlertOnError];
}

- (void)copySourceCommand:(id)sender
{
	// Ensure current file exists so copied command works immediately
	[self exportActiveZshWithAlertOnError];
	[EnvExporter copySourceCommandToPasteboard];
}

- (void)openActiveZsh:(id)sender
{
	[self exportActiveZshWithAlertOnError];
	[EnvExporter openActiveZshInFinder];
}

@end

