/**
 * 古月方源·大爱仙尊｜卷土重来
 *
 * 千古地仙随风逝，昔日三王归青冢。
 * 阳莽憾陨谁无败？卷土重来再称王。
 * 天河一挂淘龙鱼，逆天独行顾八荒。
 * 今日暂且展翼去，明朝登仙笞凤凰！
 *
 * @remarks 来源：蛊真人 · 《蛊真人》全诗词整理（完整版） · kairos-dao-header
 */
/***************************************************************************
 *   Copyright (C) 2009-2010 by Clockwise   *
 *   copyright@clockwise.ee   *
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 *   GNU General Public License for more details.                          *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   along with this program; if not, write to the                         *
 *   Free Software Foundation, Inc.,                                       *
 *   59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.             *
 ***************************************************************************/

#import "HostsMainController.h"
#import "PreferenceController.h"

@class AboutBoxController;

@interface ApplicationController : NSObject {
	@private
	IBOutlet NSProgressIndicator *busyIndicator;
	IBOutlet HostsMainController *hostsController;
	IBOutlet NSWindow *URLSheet;
	int busyThreads;
	BOOL shouldQuit;
	BOOL editorWindowOpened;
	NSArray *editorNibTopLevelObjects;
	PreferenceController *preferenceController;
    AboutBoxController *aboutBoxController;
}

+ (ApplicationController*)defaultInstance;

- (IBAction)openPreferencesWindow:(id)sender;
- (IBAction)displayAboutBox:(id)sender;
- (IBAction)reportBugs:(id)sender;
- (IBAction)donate:(id)sender;
- (IBAction)quit:(id)sender;
- (IBAction)openEditorWindow:(id)sender;
- (IBAction)closeEditorWindow:(id)sender;
- (IBAction)addFromURL:(id)sender;
- (IBAction)openHostsFile:(id)sender;
- (IBAction)updateAndSynchronize:(id)sender;
- (BOOL)editorWindowOpened;

@end
