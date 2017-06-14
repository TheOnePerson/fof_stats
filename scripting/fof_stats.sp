/*
	Universal Chatfilter
	Written by almostagreatcoder (almostagreatcoder@web.de)

	Licensed under the GPLv3
	
	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <http://www.gnu.org/licenses/>.
	
	****

	Make sure that fof_stats.cfg is in your sourcemod/configs/ directory.
	You can tweak the ranking point system there.

	CVars:
		-
	
	Commands:
		sm_top10			// show rank list
		sm_rank				// show current player's rank and statistics
		sm_rank_reload		// admin command: reload the config file
		sm_rank_givepoints	// admin command: give ranking points to player (or remove these)

*/

/**
 * TODO: proper welcome message (introducing the main rank commands)
 * TODO: play sound, if #1 connects
 * TODO: refactor playtime tracking, doesn't work currently
 * TODO: actualize config file, there are weapons missing
 */

/*
	As a preparation for a later version, in which there may be a mysql version:
*/
#define ENGINE_SQLITE

// Uncomment the line below to get a whole bunch of PrintToServer debug messages...
#define DEBUG

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <adt_trie>
#include <geoip>

#define PLUGIN_NAME 		"FoF Statistics and Ranking"
#define PLUGIN_VERSION 		"0.0.1"
#define PLUGIN_AUTHOR 		"almostagreatcoder"
#define PLUGIN_DESCRIPTION 	"Enables in-game ranking and statistics"
#define PLUGIN_URL 			"https://forums.alliedmods.net/showthread.php?t=??????"

#define CONFIG_FILENAME "fof_stats.cfg"
#define TRANSLATIONS_FILENAME "fof_stats.phrases"
#define PLUGIN_PREFIX "\x01[SM] (Ranking) \x04"
#define CHAT_COLORTAG1 "\x07FFD700"
#define CHAT_COLORTAG_NORM "\x01"
#define CHAT_COLORTAG_TEAM "\x03"

#define PLUGIN_LOGPREFIX "[FoF Stats and Ranking] "

#define MAX_WEAPONS 50

#define MAX_MESSAGE_LENGTH 128
#define STEAMID_LENGTH 25

#define COMMAND_TOP10 "sm_top10"
#define COMMAND_RANK "sm_rank"
#define COMMAND_RELOAD "sm_rank_reload"
#define COMMAND_GIVEPOINTS "sm_rank_givepoints"

#define CVAR_VERSION "sm_stats_version"

#if defined ENGINE_SQLITE
	#include <fof_stats_sqlite.inc>	// SQLite specific declarations
#endif

// Plugin definitions
public Plugin:myinfo = 
{
	name = PLUGIN_NAME, 
	author = PLUGIN_AUTHOR, 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = PLUGIN_URL
};

/*
 * Structure for config section data for weapons
 */
enum enumConfigWeaponDetails
{
	cs_WeaponIdx = 0,
	cs_PointsPerKill,
	cs_PointsPerHeadshot
};

#if defined DEBUG
	char dbgchar;
	char dbgchar2;
#endif

// global dynamic arrays
new Handle:g_WeaponDetails = INVALID_HANDLE;		// list of arrays holding the points per weapon

// global static arrays
new g_PlayerMaxKillstreak[MAXPLAYERS + 1];		// array for storing max killstreak of players (easier to handle than always requesting from db)
new g_PlayerKillstreak[MAXPLAYERS + 1];			// array for current killstreak of players
new g_PlayerRank[MAXPLAYERS + 1];
new g_PlayerPoints[MAXPLAYERS + 1];
new g_PlayerDbId[MAXPLAYERS + 1];
new bool:g_PlayerSilentInit[MAXPLAYERS + 1];	// array to determine if player data should be loaded silently during plugin startup

// other global vars
new String:g_LastError[255];	// needed for config file parsing and logging: holds the last error message
new Handle:g_db = INVALID_HANDLE;	// database connection
new g_SectionDepth;	// for config file parsing: keeps track of the nesting level of sections
new g_ConfigLine;	// for config file parsing: keeps track of the current line number
new g_currentWeaponConfig[enumConfigWeaponDetails];

new g_ServerID = 1;	// ID of the current server (normally 1)
new g_DefaultPointsPerKill = 3;
new g_DefaultPointsPerHeadshot = 5;
new g_PointsPerAssist = 1;
new g_PointsPerDeath = -2;
new g_PointsPerUngratefulDeath = -4;


//
// Handlers for public events
//

public OnPluginStart() {
	
	LoadTranslations("common.phrases");
	LoadTranslations(TRANSLATIONS_FILENAME);
	
	g_WeaponDetails = CreateArray(enumConfigWeaponDetails);
	
	CreateConVar(CVAR_VERSION, PLUGIN_VERSION, "FoF Statistics and Ranking version", FCVAR_NOTIFY | FCVAR_REPLICATED | FCVAR_DONTRECORD | FCVAR_SPONLY);
	
	RegAdminCmd(COMMAND_RELOAD, ReloadConfigHandler, ADMFLAG_CUSTOM1, "FoF Statistics and Ranking: Reload the config file");
	RegAdminCmd(COMMAND_GIVEPOINTS, PlayerCommandHandler, ADMFLAG_CUSTOM1, "FoF Statistics and Ranking: Give points to player (or remove these)");
	RegConsoleCmd(COMMAND_TOP10, Top10Handler, "FoF Statistics and Ranking: Show ranking list");
	RegConsoleCmd(COMMAND_RANK, PlayerCommandHandler, "FoF Statistics and Ranking: Show player's ranking and statistics");
#if defined DEBUG
	RegConsoleCmd("sm_stats", DebugCommandHandler, "FoF Statistics and Ranking: Debug command");
#endif
	
	SQL_OpenDB();
	
	AutoExecConfig();
	
	// Hook events
	HookEvent("player_death", Event_PlayerDeath);
	
}

public OnPluginEnd() {
	// clear the stuff read from config file
	ResetConfigArray();
}

public void OnConfigsExecuted() {
	MyLoadConfig();
	// set all clients to silent init state
	decl i;
	for (i = 0; i < sizeof(g_PlayerSilentInit); i++)
		g_PlayerSilentInit[i] = true;
	// prepare global arrays for all current players
	// TODO: potentially dangerous! ServerID may not be set, due to racing condition with MyLoadConfig() above...
	//		 (but not a problem unless multiserver functionality is about to be implemented)
	for (i = 1; i <= MaxClients; i++)
		if (IsClientConnected(i) && !IsFakeClient(i))
			OnClientPostAdminCheck(i);
		else
			ResetPlayer(i);
	
#if defined DEBUG
	PrintToServer("%sPlugin loaded, configs processed", PLUGIN_LOGPREFIX); // DEBUG
#endif
}

public void OnClientPostAdminCheck(client) {
	if (client <= MAXPLAYERS && !IsFakeClient(client)) {
#if defined DEBUG
		PrintToServer("%sConnecting client id %d...", PLUGIN_LOGPREFIX, client); // DEBUG
#endif
		g_PlayerKillstreak[client] = 0;		// should already be 0, but who knows...
		g_PlayerMaxKillstreak[client] = 0;
		g_PlayerRank[client] = 0;
		g_PlayerPoints[client] = 0;
		if (g_db != INVALID_HANDLE) {
			// Add player entry to db
			decl String:playerName[MAX_NAME_LENGTH];
			decl String:playerNameEsc[2 * MAX_NAME_LENGTH + 1];
			decl String:steamID[STEAMID_LENGTH];
			decl String:playerIp[20];
			GetClientName(client, playerName, sizeof(playerName));
			GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID));
			GetClientIP(client, playerIp, sizeof(playerIp), true);
			SQL_EscapeString(g_db, playerName, playerNameEsc, sizeof(playerNameEsc));
			decl String:Sql[SQL_MAX_LENGTH];
			Format(Sql, sizeof(Sql), SQL_INSERT_PLAYER, steamID, playerNameEsc, steamID, playerIp);
			SQL_TQuery(g_db, SQL_LogError, Sql);
			// Get player's db ID (to store it in array)
			Format(Sql, sizeof(Sql), SQL_SELECT_PLAYERID, steamID);
			SQL_TQuery(g_db, SQL_SelectPlayerID, Sql, GetClientUserId(client));
		}
		
	}
}

/**
 * Callback after executing SQL 'select player ID' / store DB id in local array and update player stats
 */
public void SQL_SelectPlayerID(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	new client = GetClientFromUserID(data, hndl, error);
	if (client > 0)
		if (SQL_FetchRow(hndl)) {
			g_PlayerDbId[client] = SQL_FetchInt(hndl, 0);
			// Insert or update playerStats entry
			decl String:Sql[SQL_MAX_LENGTH];
			decl loginInc;
			// only increment logins on new players (or else login increases every reload of this plugin)
			if (GetClientTime(client) >= 30)
				loginInc = 0;
			else
				loginInc = 1;
			Format(Sql, sizeof(Sql), SQL_INSERT_PLAYERSTAT, g_PlayerDbId[client], g_ServerID,
				g_PlayerDbId[client], g_ServerID, loginInc,
				g_PlayerDbId[client], g_ServerID,
				g_PlayerDbId[client], g_ServerID,
				g_PlayerDbId[client], g_ServerID,
				g_PlayerDbId[client], g_ServerID,
				g_PlayerDbId[client], g_ServerID,
				g_PlayerDbId[client], g_ServerID,
				g_PlayerDbId[client], g_ServerID, GetTime(), GetTime());
			SQL_TQuery(g_db, SQL_UpdatePlayerStats, Sql, data);
		}
}

/**
 * Callback after executing SQL 'update player stats' / get killstreak and points and continue
 */
public void SQL_UpdatePlayerStats(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	new client = GetClientFromUserID(data, hndl, error);
	if (client > 0) {
		decl String:Sql[SQL_MAX_LENGTH];
		// Determine max killstreak of player
		Format(Sql, sizeof(Sql), SQL_SELECT_MAXKILLSTREAK, g_PlayerDbId[client]);
		SQL_TQuery(g_db, SQL_SelectMaxKillstreak, Sql, data);
		// Get points of player
		Format(Sql, sizeof(Sql), SQL_SELECT_PLAYERPOINTS, g_PlayerDbId[client]);
		SQL_TQuery(g_db, SQL_SelectPlayerPoints, Sql, data);
	}
}

/**
 * Callback after executing SQL 'select max killstreak' / store killstreak in local array
 */
public void SQL_SelectMaxKillstreak(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	new client = GetClientFromUserID(data, hndl, error);
	if (client > 0)
		if (SQL_FetchRow(hndl))
			g_PlayerMaxKillstreak[client] = SQL_FetchInt(hndl, 0);
}

/**
 * Callback after executing SQL 'select player points' / store points in local array and get rank
 */
public void SQL_SelectPlayerPoints(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	new client = GetClientFromUserID(data, hndl, error);
	if (client > 0) {
		if (SQL_FetchRow(hndl))
			g_PlayerPoints[client] = SQL_FetchInt(hndl, 0);
		// get player's rank
		decl String:Sql[SQL_MAX_LENGTH];
		Format(Sql, sizeof(Sql), SQL_SELECT_PLAYERSRANK, g_PlayerPoints[client]);
		SQL_TQuery(g_db, SQL_SelectPlayersRank, Sql, data);
	}
}

/**
 * Callback after executing SQL 'select player's rank' / store points in local array and announce
 */
public void SQL_SelectPlayersRank(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	new client = GetClientFromUserID(data, hndl, error);
	if (client > 0) {
		if (SQL_FetchRow(hndl))
			g_PlayerRank[client] = SQL_FetchInt(hndl, 0) + 1;
		if (!g_PlayerSilentInit[client]) {
			// get total of players (for announcement)
			decl String:Sql[SQL_MAX_LENGTH];
			Format(Sql, sizeof(Sql), SQL_SELECT_TOTALPLAYERS);
			SQL_TQuery(g_db, SQL_SelectTotalPlayers, Sql, data);
		} else
			g_PlayerSilentInit[client] = false;
	}
}

/**
 * Callback after executing SQL 'select total no of players' / announce player
 */
public void SQL_SelectTotalPlayers(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	new client = GetClientFromUserID(data, hndl, error);
	if (client > 0) {
		decl totalPlayers;
		if (SQL_FetchRow(hndl))
			totalPlayers = SQL_FetchInt(hndl, 0);
		else
			totalPlayers = 0;
		// get player's country
		decl String:playerIp[20]; 
		GetClientIP(client, playerIp, sizeof(playerIp), true);
		decl String:playerCountry[50]; 
		GeoipCountry(playerIp, playerCountry, sizeof(playerCountry));
		decl String:playerName[MAX_NAME_LENGTH];
		GetClientName(client, playerName, sizeof(playerName));
		if (strlen(playerCountry) > 0) {
			// announce player with country
			PrintToChatAll("%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_NORM, "WelcomeWithCountry", playerName, playerCountry, g_PlayerRank[client], totalPlayers, g_PlayerPoints[client]);
		} else {
			// announce player without country
			PrintToChatAll("%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_NORM, "WelcomeWithoutCountry", playerName, g_PlayerRank[client], totalPlayers, g_PlayerPoints[client]);
		}
	}
}

public OnClientDisconnect(client) {
	if (client <= MAXPLAYERS)
		ResetPlayer(client);
}

/**
 * Event Handler for PlayerDeath
 */
public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast) {
	new victimId = GetEventInt(event, "userid");
	new attackerId = GetEventInt(event, "attacker");
	new assistId = GetEventInt(event, "assist");
	new weaponIdx = GetEventInt(event, "weapon_index");
	new bool:headshot = GetEventBool(event, "headshot");
	decl String:weaponName[65];
	GetEventString(event, "weapon", weaponName, sizeof(weaponName));
	
#if defined DEBUG
	decl String:msg[255];
	Format(msg, sizeof(msg), "Event_PlayerDeath: userid=%d, attacker=%d, assist=%d, headshot=%d, weapon_index=%d, weapon='%s'",  
		victimId, attackerId, assistId, headshot, weaponIdx, weaponName);
	LogMessage(msg);
#endif
	
	// reset victim's killstreak
	decl String:Sql[SQL_MAX_LENGTH];
	victimId = GetClientOfUserId(victimId);
	attackerId = GetClientOfUserId(attackerId);
	assistId = GetClientOfUserId(assistId);
	if (g_PlayerDbId[victimId] > 0) {
		g_PlayerKillstreak[victimId] = 0;
		// increase victim's death counter and substract points
		new penaltyPoints = g_PointsPerDeath;
		new ungrateful = 0;
		if (weaponIdx == -1 || victimId == attackerId) {
			// probably ungrateful death
			penaltyPoints = g_PointsPerUngratefulDeath;
			ungrateful = 1;
		}
		Format(Sql, sizeof(Sql), SQL_UPDATE_DEATHS_POINTS, ungrateful, penaltyPoints, g_PlayerDbId[victimId], g_ServerID);
		SQL_TQuery(g_db, SQL_LogError, Sql);
		// tell victim about his/her misery (in case there are points to loose)
		if (penaltyPoints != 0)
			if (ungrateful > 0)
				PrintToChat(victimId, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_TEAM, "UngratefulDeathMessage", -penaltyPoints);
				//PrintToChat(victimId, "%t", "UngratefulDeathMessage", -penaltyPoints);
			else
				PrintToChat(victimId, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_TEAM, "DeathMessage", -penaltyPoints);
				//PrintToChat(victimId, "%t", "DeathMessage", -penaltyPoints);
	}
	if (g_PlayerDbId[attackerId] > 0 && victimId != attackerId) {
		// find the weapon data and give points to attacker
		new rankPoints = GetKillPointsToWeaponIdx(weaponIdx, !headshot);
		decl headshotInc;
		if (headshot)
			headshotInc = 1;
		else
			headshotInc = 0;
		Format(Sql, sizeof(Sql), SQL_INSERT_WEAPONSTAT_KILLS, g_ServerID, g_PlayerDbId[attackerId], weaponIdx, 
			g_ServerID, g_PlayerDbId[attackerId], weaponIdx,
			g_ServerID, g_PlayerDbId[attackerId], weaponIdx, headshotInc, headshotInc);
#if defined DEBUG
		PrintToServer("%sExecuting SQL: %s", PLUGIN_LOGPREFIX, Sql); // DEBUG
#endif
		SQL_TQuery(g_db, SQL_LogError, Sql);
		Format(Sql, sizeof(Sql), SQL_UPDATE_POINTS, rankPoints, g_PlayerDbId[attackerId], g_ServerID);
#if defined DEBUG
		PrintToServer("%sExecuting SQL: %s", PLUGIN_LOGPREFIX, Sql); // DEBUG
#endif
		SQL_TQuery(g_db, SQL_LogError, Sql);
		// increase attacker's killstreak
		g_PlayerKillstreak[attackerId]++;
		if (g_PlayerKillstreak[attackerId] > g_PlayerMaxKillstreak[attackerId]) {
			// new personal killstreak record: store it!
			g_PlayerMaxKillstreak[attackerId] = g_PlayerKillstreak[attackerId];
			Format(Sql, sizeof(Sql), SQL_UPDATE_KILLSTREAK, g_PlayerMaxKillstreak[attackerId], g_PlayerDbId[attackerId], g_ServerID);
#if defined DEBUG
			PrintToServer("%sExecuting SQL: %s", PLUGIN_LOGPREFIX, Sql); // DEBUG
#endif
			SQL_TQuery(g_db, SQL_LogError, Sql);
		}
		// tell attacker about his/her fortune
		decl String:victimName[MAX_NAME_LENGTH];
		GetClientName(victimId, victimName, sizeof(victimName));
		// TODO: Insert weapon name in message!
		if (headshot)
			PrintToChat(attackerId, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_TEAM, "HeadshotMessage", rankPoints, victimName);
		else
			PrintToChat(attackerId, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_TEAM, "KillMessage", rankPoints, victimName);
	}
	if (g_PlayerDbId[assistId] > 0 && g_PointsPerAssist != 0) {
		// credit points to assisting player
		Format(Sql, sizeof(Sql), SQL_UPDATE_POINTS, g_PointsPerAssist, g_PlayerDbId[assistId], g_ServerID);
#if defined DEBUG
		PrintToServer("%sExecuting SQL: %s", PLUGIN_LOGPREFIX, Sql); // DEBUG
#endif
		SQL_TQuery(g_db, SQL_LogError, Sql);
		// increase kill assists counter
		Format(Sql, sizeof(Sql), SQL_UPDATE_KILLASSISTS, g_PlayerDbId[assistId], g_ServerID);
#if defined DEBUG
		PrintToServer("%sExecuting SQL: %s", PLUGIN_LOGPREFIX, Sql); // DEBUG
#endif
		SQL_TQuery(g_db, SQL_LogError, Sql);
		// tell assisting player about his/her fortune
		if (g_PointsPerAssist == 1)
			PrintToChat(assistId, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_TEAM, "AssistMessageSingular", g_PointsPerAssist);
		else
			PrintToChat(assistId, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_TEAM, "AssistMessagePlural", g_PointsPerAssist);
	}
}

/**
 * Handler for reloading the config file
 */
 public Action:ReloadConfigHandler(client, args) {
	MyLoadConfig();
	if (g_LastError[0] == '\0')
		ReplyToCommand(client, "%t%s%t", "ChatPrefix", CHAT_COLORTAG_TEAM, "ConfigReloaded");
	else
		ReplyToCommand(client, "%t%s%t", "ChatPrefix", CHAT_COLORTAG_TEAM, "ConfigReloadFailed", g_LastError);
	return Plugin_Handled;
}

/**
 * Handler for rank list command
 */
public Action:Top10Handler(client, args) {
 	
 	// TODO: Implement the usage of a starting row parameter!
 	decl String:Sql[SQL_MAX_LENGTH];
 	Format(Sql, sizeof(Sql), SQL_SELECT_TOP10, 0, 1000);
#if defined DEBUG
	PrintToServer("%sExecuting SQL: %s", PLUGIN_LOGPREFIX, Sql); // DEBUG
#endif
 	SQL_TQuery(g_db, SQL_ShowRanklist, Sql, GetClientUserId(client));
 	return Plugin_Handled;
}


/**
 * Handler for displaying the ranking list
 */
public SQL_ShowRanklist(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	new client = GetClientFromUserID(data, hndl, error);
	if (client > 0) {
		new Handle:menu = CreateMenu(RanklistMenuHandler);
		SetMenuTitle(menu, "%T", "RanklistTitle", client);

		new i = 1;
		while (SQL_FetchRow(hndl)) {
			new String:playerName[MAX_NAME_LENGTH];
			new String:playerSteamId[STEAMID_LENGTH];
			SQL_FetchString(hndl, 0, playerName, MAX_NAME_LENGTH);
			SQL_FetchString(hndl, 1, playerSteamId, 32);
			new playerPoints = SQL_FetchInt(hndl, 2);
			new String:menuLine[MAX_NAME_LENGTH + STEAMID_LENGTH + 30];
			Format(menuLine, sizeof(menuLine), "%i. %s (%d)", i, playerName, playerPoints);
			AddMenuItem(menu, playerSteamId, menuLine);
			i++;
		}
		SetMenuExitButton(menu, true);
		DisplayMenu(menu, client, 60);
		return;
	}
}

/**
 * Handler for ranking list inputs
 */
public RanklistMenuHandler(Handle:menu, MenuAction:action, param1, param2)
{
	// If an option was selected, tell the client about the player
	if (action == MenuAction_Select) {
		new String:info[STEAMID_LENGTH];
		GetMenuItem(menu, param2, info, sizeof(info));
		RankPanel(param1, info);
	} else 
		if (action == MenuAction_End)
			CloseHandle(menu);
}

/**
 * Initiate the panel for a player's statistics
 */
void RankPanel(client, const String:steamid[])
{
	decl String:Sql[SQL_MAX_LENGTH];
 	//Format(Sql, sizeof(Sql), SQL_SELECT_PLAYERSTATS, 0, 1000);
#if defined DEBUG
	PrintToServer("%sExecuting SQL: %s", PLUGIN_LOGPREFIX, Sql); // DEBUG
#endif
 	//SQL_TQuery(g_db, SQL_ShowRanklist, Sql, GetClientUserId(client));
}


MyLoadConfig() {
	g_SectionDepth = 0;
	g_ConfigLine = 0;
	ResetConfigArray();
	new String:g_ConfigFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, g_ConfigFile, sizeof(g_ConfigFile), "configs/%s", CONFIG_FILENAME);
	
	g_LastError = "";
	new Handle:parser = SMC_CreateParser();
	SMC_SetReaders(parser, Config_NewSection, Config_KeyValue, Config_EndSection);
	SMC_SetParseEnd(parser, Config_End);
	SMC_SetRawLine(parser, Config_NewLine);
	SMC_ParseFile(parser, g_ConfigFile);
	CloseHandle(parser);
}

public SMCResult:Config_NewLine(Handle:parser, const char[] line, int lineno) {
	g_ConfigLine = lineno;
	return SMCParse_Continue;
}

public SMCResult:Config_NewSection(Handle:parser, const String:name[], bool:quotes) {
	new SMCResult:result = SMCParse_Continue;
	g_SectionDepth++;

	if (g_SectionDepth == 2) {
		// new weapon details group
		if (GetArraySize(g_WeaponDetails) > MAX_WEAPONS) {
			result = SMCParse_Halt;
			Format(g_LastError, sizeof(g_LastError), "Error in config file line %d: Number of weapon sections exceeds limit of %d", g_ConfigLine, MAX_WEAPONS);
			LogError(g_LastError);
#if defined DEBUG
			PrintToServer("%s%s", PLUGIN_LOGPREFIX, g_LastError);
#endif
		} else {
			// store details for current section (are processed again at end of section)
			g_currentWeaponConfig[cs_WeaponIdx] = -1;
			g_currentWeaponConfig[cs_PointsPerKill] = 0;
			g_currentWeaponConfig[cs_PointsPerHeadshot] = 0;
		}
	}	// (ignore any other section nesting level...)
	return result;
}

public SMCResult:Config_KeyValue(Handle:parser, const String:key[], const String:value[], bool:key_quotes, bool:value_quotes) {
	new SMCResult:result = SMCParse_Continue;
	decl intVal;
	if (g_SectionDepth == 1) {
		// Level 1 = default values
		if (strcmp(key, "PointsPerDeath", false) == 0) {
			intVal = StringToInt(value);
			if (intVal >= -999 && intVal <= 999) {
				g_PointsPerDeath = intVal;
			} else {
				result = SMCParse_Halt;
				Format(g_LastError, sizeof(g_LastError), "Error in config file line %d: Invalid value specified for 'PointsPerDeath': %s (value must be between -999 and 999)", g_ConfigLine, value);
				LogError(g_LastError);
#if defined DEBUG
				PrintToServer("%s%s", PLUGIN_LOGPREFIX, g_LastError);
#endif
			}
		} else if (strcmp(key, "PointsPerUngratefulDeath", false) == 0) {
			intVal = StringToInt(value);
			if (intVal >= -999 && intVal <= 999) {
				g_PointsPerUngratefulDeath = intVal;
			} else {
				result = SMCParse_Halt;
				Format(g_LastError, sizeof(g_LastError), "Error in config file line %d: Invalid value specified for 'PointsPerUngratefulDeath': %s (value must be between -999 and 999)", g_ConfigLine, value);
				LogError(g_LastError);
#if defined DEBUG
				PrintToServer("%s%s", PLUGIN_LOGPREFIX, g_LastError);
#endif
			}
		} else if (strcmp(key, "PointsPerKill", false) == 0) {
			intVal = StringToInt(value);
			if (intVal >= -999 && intVal <= 999) {
				g_DefaultPointsPerKill = intVal;
			} else {
				result = SMCParse_Halt;
				Format(g_LastError, sizeof(g_LastError), "Error in config file line %d: Invalid value specified for 'PointsPerKill': %s (value must be between -999 and 999)", g_ConfigLine, value);
				LogError(g_LastError);
#if defined DEBUG
				PrintToServer("%s%s", PLUGIN_LOGPREFIX, g_LastError);
#endif
			}
		} else if (strcmp(key, "PointsPerAssist", false) == 0) {
			intVal = StringToInt(value);
			if (intVal >= -999 && intVal <= 999) {
				g_PointsPerAssist = intVal;
			} else {
				result = SMCParse_Halt;
				Format(g_LastError, sizeof(g_LastError), "Error in config file line %d: Invalid value specified for 'PointsPerAssist': %s (value must be between -999 and 999)", g_ConfigLine, value);
				LogError(g_LastError);
#if defined DEBUG
				PrintToServer("%s%s", PLUGIN_LOGPREFIX, g_LastError);
#endif
			}
		} else if (strcmp(key, "PointsPerHeadshot", false) == 0) {
			intVal = StringToInt(value);
			if (intVal >= -999 && intVal <= 999) {
				g_DefaultPointsPerHeadshot = intVal;
			} else {
				result = SMCParse_Halt;
				Format(g_LastError, sizeof(g_LastError), "Error in config file line %d: Invalid value specified for 'PointsPerHeadshot': %s (value must be between -999 and 999)", g_ConfigLine, value);
				LogError(g_LastError);
#if defined DEBUG
				PrintToServer("%s%s", PLUGIN_LOGPREFIX, g_LastError);
#endif
			}
		} else if (strcmp(key, "ServerID", false) == 0) {
			intVal = StringToInt(value);
			if (intVal >= 0 && intVal <= 999) {
				g_ServerID = intVal;
			} else {
				result = SMCParse_Halt;
				Format(g_LastError, sizeof(g_LastError), "Error in config file line %d: Invalid value specified for 'ServerID': %s (value must be between 0 and 999)", g_ConfigLine, value);
				LogError(g_LastError);
#if defined DEBUG
				PrintToServer("%s%s", PLUGIN_LOGPREFIX, g_LastError);
#endif
			}
		}
	} else if (g_SectionDepth == 2) {
		// Level 2 = weapon values
		if (strcmp(key, "WeaponIdx", false) == 0) {
			g_currentWeaponConfig[cs_WeaponIdx] = StringToInt(value);
		} else if (strcmp(key, "PointsPerKill", false) == 0) {
			intVal = StringToInt(value);
			if (intVal >= -999 && intVal <= 999) {
				g_currentWeaponConfig[cs_PointsPerKill] = intVal;
			} else {
				result = SMCParse_Halt;
				Format(g_LastError, sizeof(g_LastError), "Error in config file line %d: Invalid value specified for 'PointsPerKill': %s (value must be between -999 and 999)", g_ConfigLine, value);
				LogError(g_LastError);
#if defined DEBUG
				PrintToServer("%s%s", PLUGIN_LOGPREFIX, g_LastError);
#endif
			}
		} else if (strcmp(key, "PointsPerHeadshot", false) == 0) {
			intVal = StringToInt(value);
			if (intVal >= -999 && intVal <= 999) {
				g_currentWeaponConfig[cs_PointsPerHeadshot] = intVal;
			} else {
				result = SMCParse_Halt;
				Format(g_LastError, sizeof(g_LastError), "Error in config file line %d: Invalid value specified for 'PointsPerHeadshot': %s (value must be between -999 and 999)", g_ConfigLine, value);
				LogError(g_LastError);
#if defined DEBUG
				PrintToServer("%s%s", PLUGIN_LOGPREFIX, g_LastError);
#endif
			}
		}
	}
	return result;
}

public SMCResult:Config_EndSection(Handle:parser) {
	new SMCResult:result = SMCParse_Continue;
	if (g_SectionDepth == 2) {
		// weapon details group ending
		PushArrayArray(g_WeaponDetails, g_currentWeaponConfig[0]);
	}
	g_SectionDepth--;
	return result;
}

public Config_End(Handle:parser, bool:halted, bool:failed) {
	if (halted)
		LogError("Configuration parsing stopped!");
	if (failed)
		LogError("Configuration parsing failed!");
	if (!failed && !halted) {
		// TODO: Write server entry into database (..not important for now)
	}
}

/**
 * Handler for map start
 */
public void OnMapStart() {
	// reset all player data
	ResetPlayer(0);
	// start the timer for tracking the playtime
	CreateTimer(60.0, Timer_Playtime, TIMER_REPEAT + TIMER_FLAG_NO_MAPCHANGE);
}


/**
 * Handler for keeping track of the players playtimes. 
 * 
 * @param timer 		handle for the timer
 * @param client		client id
 */
public Action:Timer_Playtime(Handle:timer) {
	// increment the playtime of all current players
	new String:playerIDs[(MAXPLAYERS + 1) * 10] = "";
	for (new i = 1; i < MaxClients; i++) 
		if (IsClientInGame(i) && !IsFakeClient(i) && g_PlayerDbId[i] > 0)
			Format(playerIDs[strlen(playerIDs)], 10, "%d,", g_PlayerDbId[i]);
	if (strlen(playerIDs) > 0) {
		playerIDs[strlen(playerIDs) - 1] = 0;
		decl String:Sql[SQL_MAX_LENGTH];
		Format(Sql, sizeof(Sql), SQL_UPDATE_PLAYTIME, 60, playerIDs, g_ServerID);
#if defined DEBUG
		PrintToServer("%sExecuting SQL: %s", PLUGIN_LOGPREFIX, Sql); // DEBUG
#endif
		SQL_TQuery(g_db, SQL_LogError, Sql);
	}
}


/**
 * Handler for all player related commands. These are: 'sm_chatfilter_reset', 'sm_chatfilter_group',
 * and 'sm_chatfilter_ungroup'. 
 * 
 * @param client 	client id
 * @args			Arguments given for the command
 *
 */
public Action:PlayerCommandHandler(client, args) {
	new commandType = 0;
	// determine command
	decl String:strTarget[MAX_NAME_LENGTH];
	GetCmdArg(0, strTarget, sizeof(strTarget));
	if (strcmp(strTarget, COMMAND_RANK, false) == 0)
		commandType = 1;
	else if (strcmp(strTarget, COMMAND_GIVEPOINTS, false) == 0)
		commandType = 2;
	else 
		commandType = 0;
	
	if (args != 2 && commandType == 2)
		ReplyToCommand(client, "%sUsage: %s <name|#userid> [<points>]", PLUGIN_PREFIX, strTarget);
	else if (args > 1 && commandType == 1)
		ReplyToCommand(client, "%sUsage: %s [<name|#userid>]", PLUGIN_PREFIX, strTarget);
	else {
		GetCmdArg(1, strTarget, sizeof(strTarget));
		
		new String:targetName[MAX_TARGET_LENGTH];
		decl targetList[MAXPLAYERS + 1];
		decl targetCount;
		new bool:tn_is_ml;
		if ((targetCount = ProcessTargetString(
					strTarget, 
					client, 
					targetList, 
					MAXPLAYERS, 
					COMMAND_FILTER_CONNECTED + COMMAND_FILTER_NO_BOTS, 
					targetName, 
					sizeof(targetName), 
					tn_is_ml)) <= 0) {
			ReplyToTargetError(client, targetCount);
		} else {
			decl String:param2[MAX_TARGET_LENGTH];
			if (args >= 2)
				GetCmdArg(2, param2, sizeof(param2));
			for (new i = 0; i < targetCount; i++) {
				switch (commandType) {
					case 1: {
						// COMMAND_RANK
						new showClient = client;
						// TODO: Implement it!
					}
					case 2: {
						// COMMAND_GIVEPOINTS
						new points = StringToInt(param2);
						if (points == 0 || points < -9999 || points > 9999) {
							ReplyToCommand(client, "%sAmount of ranking points must be in the range between -9999 and +9999", PLUGIN_PREFIX);
						} else {
							// TODO: Implement it!
							decl String:word[10];
							if (points < 0) {
								word = "decreased";
								points = -points;
							} else
								word = "increased";
							ReplyToCommand(client, "%s%N's ranking points have been %s by %d.", PLUGIN_PREFIX, targetList[i], word, points);
						}
					}
				}
			}
		}
	}
	return Plugin_Handled;
}

#if defined DEBUG
/**
 * Debugging only: Command handler for trying things out
 * 
 * @param client 	client id
 * @args			Arguments given for the command
 *
 */
public Action:DebugCommandHandler(client, args) {
	// determine command
	decl String:strTarget[MAX_NAME_LENGTH];
	if (args > 0) GetCmdArg(1, strTarget, sizeof(strTarget));
	PrintToServer("%s****", PLUGIN_LOGPREFIX);
	PrintToServer("%sDebug command executed!!!", PLUGIN_LOGPREFIX);
	PrintToServer("%s****", PLUGIN_LOGPREFIX);
	PrintToChat(client, "\x01\\x01 \x02\\x02 \x03\\x03 \x04\\x04 \x05\\x05 \x06\\x06");
	// PrintToChat(client, "%t", "DebugMessage", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_NORM, client, g_PlayerRank[client]);
	return Plugin_Handled;
}
#endif

//
// Private functions
//


/** 
 * Charges the penalty points contained in the g_MatchedSections array to a client
 * and increments the hit counter. The client's cookie is NOT set here.
 *
 * @param client				client id
 * @param penalty				penalty points to be charged
 * @noreturn
 */
void ChargePoints(const client) {
	g_PlayerHits[client] += 1;
	new max = GetArraySize(g_MatchedSections);
	decl thisPP[MAXPLAYERS + 1];
	for (new i = 0; i < max; i++) {
		// somewhat tricky: first copy the needed config section information into g_currentSection
		GetArrayArray(g_ConfigSections, GetArrayCell(g_MatchedSections, i), g_currentSection[0]);
		// then get the right penalty pointer arry, modify it and write it back
		GetArrayArray(g_PlayerPenaltyPoints, g_currentSection[cs_actionGroupIdx], thisPP[0]);
		thisPP[client] += g_currentSection[cs_penalty];
		SetArrayArray(g_PlayerPenaltyPoints, g_currentSection[cs_actionGroupIdx], thisPP[0]);
	}
}

/** 
 * Finds the correct kill or headshot points to a given weapon idx.
 * Sets the correct values directly in rankPoints or headshotPoints.
 *
 * @param client				client id
 * @param getKillPoints			true to receive kill points, false to receive headshot points 
 * @return
 */
GetKillPointsToWeaponIdx(const weaponIdx, const bool:getKillPoints) {
	new max = GetArraySize(g_WeaponDetails);
	new thisWC[enumConfigWeaponDetails];
	decl points;
	if (getKillPoints) 
		points = g_DefaultPointsPerKill;
	else
		points = g_DefaultPointsPerHeadshot;
	for (new i = 0; i < max; i++) {
		GetArrayArray(g_WeaponDetails, i, thisWC[0]);
		if (thisWC[cs_WeaponIdx] == weaponIdx) {
			if (getKillPoints) 
				points = thisWC[cs_PointsPerKill];
			else
				points = thisWC[cs_PointsPerHeadshot];
			break;
		}
	}
	return points;
}

/** 
 * Clean up on exit and close all handles
 *
 * @noreturn
 */
void ResetConfigArray() {
	ClearArray(g_WeaponDetails);
	ResetPlayer(0);
}

/** 
 * Resets the points for a single or all players
 *
 * @param client 	client id (0 = reset all players)
 * @noreturn
 */
void ResetPlayer(const client) {
	if (client == 0) {
		decl i;
		for (i = 0; i < sizeof(g_PlayerKillstreak); i++) {
			g_PlayerKillstreak[i] = 0;
			g_PlayerMaxKillstreak[i] = -1;
			g_PlayerRank[i] = -1;
			g_PlayerDbId[client] = -1;
			g_PlayerPoints[client] = -1;
		}
	} else if (client >= 0 && client < sizeof(g_PlayerKillstreak)) {
		g_PlayerKillstreak[client] = 0;
		g_PlayerMaxKillstreak[client] = -1;
		g_PlayerRank[client] = -1;
		g_PlayerDbId[client] = -1;
		g_PlayerPoints[client] = -1;
	}
}

/**
 * Calculates the printed length of a string - multibyte-safe!
 *
 */
stock StrLenMB(const String:str[])
{
	new len = strlen(str);
	new count;
	for(new i; i < len; i++)
		count += ((str[i] & 0xc0) != 0x80) ? 1 : 0;
	return count;
}

//
// Database functions
//

/**
 * Open database or create it, if needed
 */
bool:SQL_OpenDB() {
	new bool:Result = false;
	if (SQL_CheckConfig(SQL_DEFAULTDBNAME))
		SQL_TConnect(SQL_Connected, SQL_DEFAULTDBNAME);
	else {
		new Handle:kv;
		kv = CreateKeyValues("");
		KvSetString(kv, "driver", SQL_DBDRIVERNAME);
		KvSetString(kv, "database", SQL_DEFAULTDBNAME);
		g_db = SQL_ConnectCustom(kv, g_LastError, sizeof(g_LastError), false);
		CloseHandle(kv);		
		
		if (g_db == INVALID_HANDLE)
			LogMessage("%sFailed to connect to database '%s': %s", PLUGIN_LOGPREFIX, SQL_DEFAULTDBNAME, g_LastError);
		else {
			LogMessage("%sSucessfully connected to %s database '%s'", PLUGIN_LOGPREFIX, SQL_DBTYPE, SQL_DEFAULTDBNAME);
			SQL_InitDB();
			Result = true;
		}
	}
	return Result;
}

/**
 * Callback function for connecting to database 
 */
public void SQL_Connected(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE || !StrEqual(error, ""))	{
		LogMessage("%sFailed to connect to database '%s': %s", PLUGIN_LOGPREFIX, SQL_DEFAULTDBNAME, error);
		SetFailState("%sCould not reach database '%s'! Error: %s", PLUGIN_LOGPREFIX, SQL_DEFAULTDBNAME, error);
		return;
	} else {
		LogMessage("%sSucessfully connected to SQLite database '%s'", PLUGIN_LOGPREFIX, SQL_DEFAULTDBNAME);
		g_db = hndl;
		SQL_InitDB();
	}
}

/**
 * Initialize database; also handle schema updates
 */
void SQL_InitDB() {
 	
	if (g_db != INVALID_HANDLE) {
		SQL_FastQuery(g_db, SQL_CREATE_TBL_Players);
		SQL_FastQuery(g_db, SQL_CREATE_TBL_Players_Idx);
		SQL_FastQuery(g_db, SQL_CREATE_TBL_PlayerStats);
		SQL_FastQuery(g_db, SQL_CREATE_TBL_PlayerStats_Idx1);
		SQL_FastQuery(g_db, SQL_CREATE_TBL_PlayerStats_Idx2);
		SQL_FastQuery(g_db, SQL_CREATE_TBL_Servers);
		SQL_FastQuery(g_db, SQL_CREATE_TBL_Version);
		SQL_FastQuery(g_db, SQL_CREATE_TBL_WeaponStats);
		// TODO: Check schema version and apply changes (currently there are none of these, so we're fine...)
	}
}

/**
 * Callback after executing SQL: If an error occurs, just log it
 */
public void SQL_LogError(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (strlen(error) != 0)
		LogError("SQL error occured: %s", error);
}

/**
 * Callback after executing SQL: If an error occurs, stop the plugin (for critical queries)
 */
public void SQL_StopOnError(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (strlen(error) != 0)
		SetFailState("Critical SQL error occured: %s", error);
}

/**
 * Return client to user id and check given handle (default check routine for SQL callback handlers)
 */
GetClientFromUserID(const userid, const Handle:handle, const String:error[]) {
	if (handle == INVALID_HANDLE || strlen(error) > 0) {
		LogError("SQL error occured: %s", error);
		return 0;
	} else
		return GetClientOfUserId(userid);
}


//
// Debug functions - not to be meant in release version!
//

#if defined DEBUG

void Debug_PrintArray(const Handle:arrayHandle, const bool:isNum) {
	decl value;
	decl String:valueString[255];
	for (new i = 0; i < GetArraySize(arrayHandle); i++) {
		if (isNum) {
			value = GetArrayCell(arrayHandle, i);
			PrintToServer("%d: %d", i, value);
		} else {
			GetArrayString(arrayHandle, i, valueString, sizeof(valueString));
			PrintToServer("%d: %s", i, valueString);
		}
	}
}

#endif