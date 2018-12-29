/*
	Fistful of Frags Ranking and Statistics
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

	Important advice to potential fellow developers: 
	You will find an ugly mix of old syntax and new transitional sourcepawn
	syntax in this plugin code. You know how it goes: you have existing
	code that you re-use, you have new parts to code, and you also have
	a life, so you don't want to rewrite *everything* from scratch! ;-)
	So: if you happen to use some of the lines below for your own plugin,
	please don't be as lazy as I have been! Better do it properly and stick 
	to the new transitional syntax. Thank you!
	
	****

	Make sure that fof_rank.cfg is in your sourcemod/configs/ directory.
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
 * TODO: implement killstreak top 10 (perhaps...)
 */

// Uncomment the line below to get a whole bunch of PrintToServer debug messages...
//#define DEBUG

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <adt_trie>
#include <geoip>

#define PLUGIN_NAME 		"FoF Ranking and Statistics"
#define PLUGIN_VERSION 		"1.2.2"
#define PLUGIN_AUTHOR 		"almostagreatcoder"
#define PLUGIN_DESCRIPTION 	"Enables in-game ranking and statistics"
#define PLUGIN_URL 			"https://forums.alliedmods.net/showthread.php?t=298634"

#define CONFIG_FILENAME 	"fof_rank.cfg"
#define TRANSLATIONS_FILENAME "fof_rank.phrases"
#define CHAT_COLORTAG1 		"\x0794D8E9"
#define CHAT_COLORTAG_RED	"\x07DB4646"
#define CHAT_COLORTAG_GOLD	"\x07D4B51A"
#define CHAT_COLORTAG_NORM 	"\x01"
#define CHAT_COLORTAG_TEAM 	"\x03"

#define PLUGIN_LOGPREFIX 	"[Ranking] "

#define MAX_WEAPONS 60
#define MAX_PANELLINE_LENGTH 80
#define STEAMID_LENGTH 25
#define DEFAULT_IDLESECS 30 * 24 * 60 * 60
#define KILLER_LIST_ITEMS 10

#define COMMAND_TOP10 "sm_top10"
#define COMMAND_RANK "sm_rank"
#define COMMAND_RELOAD "sm_rank_reload"
#define COMMAND_GIVEPOINTS "sm_giverankpoints"

#define CVAR_VERSION "sm_rank_version"
#define CVAR_ENABLED "sm_rank_enabled"
#define CVAR_DBENGINE "sm_rank_db_engine"
#define CVAR_ANNOUNCEPLAYERS "sm_rank_announceplayers"
#define CVAR_SHOWPANELS "sm_rank_showpanels"
#define CVAR_INFORMPOINTS "sm_rank_informpoints"
#define CVAR_ROUNDSUMMARY "sm_rank_roundsummary"

#include <fof_rank_sqls.inc>	// Database specific functions

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

// cvar handles
new Handle:g_CvarEnabled = INVALID_HANDLE;
new Handle:g_CvarAnnouncePlayers = INVALID_HANDLE;
new Handle:g_CvarShowPanels = INVALID_HANDLE;
new Handle:g_CvarInformPoints = INVALID_HANDLE;
new Handle:g_CvarRoundSummary = INVALID_HANDLE;

new Handle:g_CvarFofCurrentMode = INVALID_HANDLE;
new Handle:g_CvarFofWarmupTime = INVALID_HANDLE;

// global dynamic arrays
new Handle:g_WeaponDetails = INVALID_HANDLE;	// list of arrays holding the points per weapon
new Handle:g_ClientsToInit = INVALID_HANDLE;	// list of client id, that need to be initialized (in case OnClientPostAdminCheck was initiated too early)


// global static arrays
new g_PlayerMaxKillstreak[MAXPLAYERS + 1];		// array for storing max killstreak of players (easier to handle than always requesting from db)
new g_PlayerKillstreak[MAXPLAYERS + 1];			// array for current killstreak of players
new g_PlayerPreviousLogin[MAXPLAYERS + 1];		// needed for welcome panel on spawns
new g_PlayerSpawnedAt[MAXPLAYERS + 1];			// array for keeping track of the time alive of a player
new g_CurrentMenuState[MAXPLAYERS + 1][2];		// for storing the state of the ranking list menu when a ranking panel is displayed as a sub menu
new g_CurrentStatsPlayerId[MAXPLAYERS + 1];		// for storing the id of the player whose statistics are currently shown on a panel
new g_PlayerDbId[MAXPLAYERS + 1];				// stores the id in table Players for each client
new bool:g_PlayerSilentInit[MAXPLAYERS + 1];	// array to determine if player data should be loaded silently during plugin startup
new g_PlayerPointsAtRoundstart[MAXPLAYERS + 1];	// stores each clients points when the round started
new g_PlayerRankAtRoundstart[MAXPLAYERS + 1];	// stores each clients rank when the round started
new g_PlayerPoints[MAXPLAYERS + 1];				// stores each clients current points

// other global vars
new String:g_LastError[255];					// needed for config file parsing and logging: holds the last error message
new Handle:g_db = INVALID_HANDLE;				// database connection
new g_SectionDepth;								// for config file parsing: keeps track of the nesting level of sections
new g_ConfigLine;								// for config file parsing: keeps track of the current line number
new g_currentWeaponConfig[enumConfigWeaponDetails];

new g_ServerID = 1;								// ID of the current server (normally 1)
new bool:g_SQLite = true;
new bool:g_DBInit = false;
new bool:g_Enabled = true;
new bool:g_Warmup = false;
new bool:g_AnnouncePlayers = true;
new bool:g_ShowPanels = true;
new bool:g_InformAboutPoints = true;
new bool:g_RoundSummary = true;
new bool:g_RoundTimer = false;
new g_MaxIdleSecs = DEFAULT_IDLESECS;
new g_ActivePlayers = 0;
new g_DefaultPointsPerKill = 3;
new g_DefaultPointsPerHeadshot = 5;
new g_PointsPerAssist = 1;
new g_PointsPerDeath = -2;
new g_PointsPerUngracefulDeath = -4;


//
// Handlers for public events
//

public OnPluginStart() {
	
	LoadTranslations("common.phrases");
	LoadTranslations("core.phrases");
	LoadTranslations(TRANSLATIONS_FILENAME);
	
	g_WeaponDetails = CreateArray(enumConfigWeaponDetails);
	g_ClientsToInit = CreateArray();
	g_DBInit = false;
	
	CreateConVar(CVAR_VERSION, PLUGIN_VERSION, "FoF Ranking and Statistics version", FCVAR_NOTIFY | FCVAR_REPLICATED | FCVAR_DONTRECORD | FCVAR_SPONLY);
	g_CvarEnabled = CreateConVar(CVAR_ENABLED, "1", "1 enables the FoF Ranking plugin, 0 disables it.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_CvarAnnouncePlayers = CreateConVar(CVAR_ANNOUNCEPLAYERS, "1", "If set to 1, every new player is announced to others on login.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_CvarShowPanels = CreateConVar(CVAR_SHOWPANELS, "1", "If set to 1, a connecting player is presented a ranking information panel.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_CvarInformPoints = CreateConVar(CVAR_INFORMPOINTS, "1", "If set to 1, every player gets ranking information on kills or deaths as chat messages.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_CvarRoundSummary = CreateConVar(CVAR_ROUNDSUMMARY, "1", "If set to 1, every player sees a summary about his/her rank and gained/lost points at the end of each round.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_CvarFofCurrentMode = FindConVar("fof_sv_currentmode");
	g_CvarFofWarmupTime = FindConVar("fof_sv_obj_warmuptime");
	
	RegAdminCmd(COMMAND_RELOAD, ReloadConfigHandler, ADMFLAG_CUSTOM1, "FoF Statistics and Ranking: Reload the config file");
	RegAdminCmd(COMMAND_GIVEPOINTS, PlayerCommandHandler, ADMFLAG_CUSTOM1, "FoF Statistics and Ranking: Give points to player (or remove these)");
	RegConsoleCmd(COMMAND_TOP10, Top10Handler, "FoF Statistics and Ranking: Show ranking list");
	RegConsoleCmd(COMMAND_RANK, RankCommandHandler, "FoF Statistics and Ranking: Show player's ranking and statistics");
#if defined DEBUG
	RegConsoleCmd("sm_rank_debug", DebugCommandHandler, "FoF Statistics and Ranking: Debug command");
#endif
	
	// Hook cvar changes
	HookConVarChange(g_CvarEnabled, CVar_EnabledChanged);
	HookConVarChange(g_CvarAnnouncePlayers, CVar_AnnouncePlayersChanged);
	HookConVarChange(g_CvarShowPanels, CVar_ShowPanelsChanged);
	HookConVarChange(g_CvarInformPoints, CVar_InformPointsChanged);
	HookConVarChange(g_CvarRoundSummary, CVar_RoundSummaryChanged);
	
	AutoExecConfig();

	// Hook events
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("round_end", Event_RoundEnd);

}

public OnPluginEnd() {
	// clear the stuff read from config file
	ResetConfigArray();
}

public void OnConfigsExecuted() {
	MyLoadConfig();
	
	SQL_OpenDB();
	
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
}

/**
 * CVar handlers
 */
public CVar_EnabledChanged(Handle:cvar, const String:oldval[], const String:newval[]) {
	decl String:tag[50];
	if (strcmp(newval, "0") == 0) {
		g_Enabled = false;
		strcopy(tag, sizeof(tag), "CVarMessageEnabled");
	} else {
		g_Enabled = true;
		strcopy(tag, sizeof(tag), "CVarMessageDisabled");
	}
	PrintToChatAll("%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_NORM, tag);
}
public CVar_AnnouncePlayersChanged(Handle:cvar, const String:oldval[], const String:newval[]) {
	g_AnnouncePlayers = !(strcmp(newval, "0") == 0);
}
public CVar_ShowPanelsChanged(Handle:cvar, const String:oldval[], const String:newval[]) {
	g_ShowPanels = !(strcmp(newval, "0") == 0);
}
public CVar_InformPointsChanged(Handle:cvar, const String:oldval[], const String:newval[]) {
	g_InformAboutPoints = !(strcmp(newval, "0") == 0);
}
public CVar_RoundSummaryChanged(Handle:cvar, const String:oldval[], const String:newval[]) {
	g_RoundSummary = !(strcmp(newval, "0") == 0);
}


/**
 * Handler for connecting clients
 */
public void OnClientPostAdminCheck(client) {
	if (client <= MaxClients && !IsFakeClient(client)) {
#if defined DEBUG
		PrintToServer("%sConnecting client id %d... / db handle = %d", PLUGIN_LOGPREFIX, client, g_db); // DEBUG
#endif
		g_PlayerKillstreak[client] = 0;		// should already be 0, but who knows...
		g_PlayerMaxKillstreak[client] = 0;
		g_PlayerPreviousLogin[client] = 0;
		g_PlayerPointsAtRoundstart[client] = 0;
		g_PlayerPoints[client] = 0;
		g_PlayerRankAtRoundstart[client] = 0;
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
			// Format(Sql, sizeof(Sql), SQL_INSERT_PLAYER, steamID, playerNameEsc, steamID, playerIp);
			DB_Format_SQL_INSERT_PLAYER(g_SQLite, Sql, sizeof(Sql), steamID, playerNameEsc, playerIp);
			SQL_TQuery(g_db, SQL_LogError, Sql);
			// Get player's db ID (to store it in array)
			Format(Sql, sizeof(Sql), SQL_SELECT_PLAYERID, steamID);
			SQL_TQuery(g_db, SQL_SelectPlayerID, Sql, GetClientUserId(client));
		} else
			if (!g_DBInit) PushArrayCell(g_ClientsToInit, client);
	}
}

/**
 * Callback after executing SQL 'select player ID' / store DB id in local array and prepare welcome actions
 */
public void SQL_SelectPlayerID(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	new client = GetClientFromUserID(data, hndl, error);
#if defined DEBUG
	PrintToServer("%sExecuting SQL_SelectPlayerID for client %d...", PLUGIN_LOGPREFIX, client); // DEBUG
#endif
	if (client > 0)
		if (SQL_FetchRow(hndl)) {
			g_PlayerDbId[client] = SQL_FetchInt(hndl, 0);
#if defined DEBUG
			PrintToServer("%s+++++ client %d has database id %D +++++", PLUGIN_LOGPREFIX, client, g_PlayerDbId[client]); // DEBUG
#endif
			// Insert or update playerstats entry
			decl String:Sql[SQL_MAX_LENGTH];
			decl loginInc;
			// only increment logins on new players (or else login increases every reload of this plugin)
			if (GetClientTime(client) >= 30)
				loginInc = 0;
			else
				loginInc = 1;
			DB_Format_SQL_INSERT_PLAYERSTAT(g_SQLite, Sql, sizeof(Sql), g_PlayerDbId[client], g_ServerID, loginInc);
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
		// Determine max killstreak of player for initializing the global array value
		Format(Sql, sizeof(Sql), SQL_SELECT_MAXKILLSTREAK, g_PlayerDbId[client]);
		SQL_TQuery(g_db, SQL_SelectMaxKillstreak, Sql, data);
		// Get data of player
		new timeLimit = GetTime() - g_MaxIdleSecs;
		Format(Sql, sizeof(Sql), SQL_SELECT_DATAONCONNECT, g_ServerID, timeLimit, g_PlayerDbId[client], timeLimit, g_PlayerDbId[client]);
		SQL_TQuery(g_db, SQL_SelectPlayerDataOnConnect, Sql, data);
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
 * Callback after executing SQL 'select player data on connect' / store some data in local array and announce player to others
 */
public void SQL_SelectPlayerDataOnConnect(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	new client = GetClientFromUserID(data, hndl, error);
	if (client > 0)
		if (SQL_FetchRow(hndl)) {
			g_PlayerPreviousLogin[client] = SQL_FetchInt(hndl, 1);
			// Now, after getting the last login time, update it
			decl String:Sql[SQL_MAX_LENGTH];
			Format(Sql, sizeof(Sql), SQL_UPDATE_LASTENTER, GetTime(), g_PlayerDbId[client], g_ServerID);
			SQL_TQuery(g_db, SQL_RefreshActivePlayers, Sql, data);
			// Store player's rank and points in array
			new rank = SQL_FetchInt(hndl, 2);
			new points = SQL_FetchInt(hndl, 0);
			g_PlayerRankAtRoundstart[client] = rank;
			g_PlayerPointsAtRoundstart[client] = points;
			g_PlayerPoints[client] = points;
#if defined DEBUG
			PrintToServer("%s+++++ Announcing client %d , silentInit: %d, PlayerPreviousLogin: %d +++++", PLUGIN_LOGPREFIX, client, g_PlayerSilentInit[client], g_PlayerPreviousLogin[client]); // DEBUG
#endif
			// Announce player if applicable
			if (!g_PlayerSilentInit[client] && g_AnnouncePlayers && g_Enabled) {
				g_PlayerSilentInit[client] = false;
				// get player's country
				decl String:playerIp[20]; 
				GetClientIP(client, playerIp, sizeof(playerIp), true);
				decl String:playerCountry[50]; 
				GeoipCountry(playerIp, playerCountry, sizeof(playerCountry));
				decl String:playerName[MAX_NAME_LENGTH];
				GetClientName(client, playerName, sizeof(playerName));
				if (strlen(playerCountry) > 0) {
					// announce player with country
					if (g_PlayerPreviousLogin[client] > 0) {
						// player has been here once - announce with ranking information
						if (rank == 1) {
							// wow - No 1 is coming!
							PrintToChatAll("%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_NORM, "AnnounceWithRankAndCountryNo1", 
								playerName, playerCountry, rank, SQL_FetchInt(hndl, 3), points, 
								CHAT_COLORTAG_TEAM, CHAT_COLORTAG_NORM, CHAT_COLORTAG_TEAM, CHAT_COLORTAG_NORM, CHAT_COLORTAG1, CHAT_COLORTAG_GOLD, CHAT_COLORTAG_NORM);
						} else {
							// just a regular player...
							PrintToChatAll("%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_NORM, "AnnounceWithRankAndCountry", 
								playerName, playerCountry, rank, SQL_FetchInt(hndl, 3), points, 
								CHAT_COLORTAG_TEAM, CHAT_COLORTAG_NORM, CHAT_COLORTAG_TEAM, CHAT_COLORTAG_NORM, CHAT_COLORTAG_GOLD, CHAT_COLORTAG_NORM);
						}
					} else {
						// player is here for the first time - just tell the name
						PrintToChatAll("%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_NORM, "AnnounceWithCountry", 
								playerName, playerCountry, CHAT_COLORTAG_TEAM, CHAT_COLORTAG_NORM);
					}
				} else {
					// announce player without country
					if (g_PlayerPreviousLogin[client] > 0) {
						// player has been here once - announce with ranking information
						if (rank == 1) {
							// wow - No 1 is coming!
							PrintToChatAll("%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_NORM, "AnnounceWithRankNo1", 
								playerName, rank, SQL_FetchInt(hndl, 3), points, 
								CHAT_COLORTAG_TEAM, CHAT_COLORTAG_NORM, CHAT_COLORTAG_TEAM, CHAT_COLORTAG_NORM, CHAT_COLORTAG1, CHAT_COLORTAG_GOLD, CHAT_COLORTAG_NORM);
						} else {
							// just a regular player...
							PrintToChatAll("%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_NORM, "AnnounceWithRank", 
								playerName, rank, SQL_FetchInt(hndl, 3), points, 
								CHAT_COLORTAG_TEAM, CHAT_COLORTAG_NORM, CHAT_COLORTAG_TEAM, CHAT_COLORTAG_NORM, CHAT_COLORTAG_GOLD, CHAT_COLORTAG_NORM);
						}
					} else {
						// player is here for the first time - just tell the name
						PrintToChatAll("%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_NORM, "Announce", 
								playerName, CHAT_COLORTAG_TEAM, CHAT_COLORTAG_NORM);
					}
				}
			}
		}
}

/**
 * Callback for refreshing the no. of active players in db
 */
public void SQL_RefreshActivePlayers(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	// refresh total number of active players
	decl String:Sql[SQL_MAX_LENGTH];
	Format(Sql, sizeof(Sql), SQL_SELECT_TOTALPLAYERS, GetTime() - g_MaxIdleSecs);
	SQL_TQuery(g_db, SQL_GotTotalPlayers, Sql);
}

public void SQL_GotTotalPlayers(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl != INVALID_HANDLE && strlen(error) == 0)
		if (SQL_FetchRow(hndl))
			// store current no of active players
			g_ActivePlayers = SQL_FetchInt(hndl, 0);
}

/**
 * Clean up on disconnecting clients
 */
public OnClientDisconnect(client) {
	if (client <= MaxClients) {
		ResetPlayer(client);
	}
}

/**
 * Event Handler for PlayerSpawn (store the ClientTime and spawns to be able to determine average time alive)
 */
public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast) {
	// check if a round summary timer should be set
	if (g_RoundSummary && !g_RoundTimer) {
		decl timeleft;
		GetMapTimeLeft(timeleft);
		if (g_CvarFofWarmupTime != INVALID_HANDLE)
			timeleft += GetConVarInt(g_CvarFofWarmupTime);
#if defined DEBUG
		// PrintToServer("%s>>>> First Player spawned. Timeleft = %d", PLUGIN_LOGPREFIX, timeleft);
#endif
		CreateTimer(float(timeleft - 9), Timer_RoundSummary, INVALID_HANDLE, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		g_RoundTimer = true;

	}
	// now handle client related stuff
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!IsFakeClient(client) && g_Enabled) {
		new playtime = RoundToZero(GetClientTime(client));
		g_PlayerSpawnedAt[client] = playtime;
		if (g_db != INVALID_HANDLE) {
			decl String:Sql[SQL_MAX_LENGTH];
			Format(Sql, sizeof(Sql), SQL_UPDATE_SPAWNS, g_PlayerDbId[client], g_ServerID);
			SQL_TQuery(g_db, SQL_LogError, Sql);
		}
		
#if defined DEBUG
		// PrintToServer("%s+++++ Event_PlayerSpawn +++++ / Current Time: %d, Last Login: %d, Delta: %d", PLUGIN_LOGPREFIX, GetTime(), g_PlayerPreviousLogin[client], GetTime() - g_PlayerPreviousLogin[client]); // DEBUG
		// Just for testing...
		//decl String:playerName[MAX_NAME_LENGTH];
		//GetClientName(client, playerName, sizeof(playerName));
		//if (strcmp(playerName, "almostagreatplayer") == 0)
		//	g_PlayerPreviousLogin[client] = 0;
#endif
		if (g_ShowPanels) {
			if (g_PlayerPreviousLogin[client] == 0) {
				// first login on this server - show explanation panel
				g_PlayerPreviousLogin[client] = 1;
				CreateTimer(1.0, Timer_InitExplanationPanel, client);
			} else if (g_PlayerPreviousLogin[client] > 1 && (GetTime() - g_PlayerPreviousLogin[client]) > 2 * 60 * 60) {
				// last login more than 2 hours ago - show welcome panel
				g_PlayerPreviousLogin[client] = 1;
				CreateTimer(2.0, Timer_InitWelcomePanel, client);
			}
		}
	}
}

/**
 * Handler for the timer to display the welcome panel to a player 
 * 
 * @param timer 		handle for the timer
 * @param client		client id
 */
public Action:Timer_InitWelcomePanel(Handle:timer, any:client) {
	if (IsClientConnected(client) && !IsFakeClient(client)) {
		decl String:Sql[SQL_MAX_LENGTH];
		Format(Sql, sizeof(Sql), SQL_SELECT_PLAYERSRANK2, g_PlayerDbId[client], GetTime() - g_MaxIdleSecs, g_PlayerDbId[client]);
		SQL_TQuery(g_db, SQL_GotRankForStatisticsPanel, Sql, GetClientUserId(client));
	}
	return Plugin_Stop;
}

/**
 * Handler for the timer to display an initial explanation to the player 
 * 
 * @param timer 		handle for the timer
 * @param client		client id
 */
public Action:Timer_InitExplanationPanel(Handle:timer, any:client) {
	if (IsClientConnected(client) && !IsFakeClient(client) && (g_db != INVALID_HANDLE)) {
		decl String:Sql[SQL_MAX_LENGTH];
		Format(Sql, sizeof(Sql), SQL_SELECT_TOP10, GetTime() - g_MaxIdleSecs, 0, 3);
		SQL_TQuery(g_db, SQL_InitExplanationPanel, Sql, GetClientUserId(client));
	}
	return Plugin_Stop;
}

/**
 * Event Handler for RoundEnd (store the times alive in database and show round summary)
 */
public Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast) {
	// store times alive in db
	for (new i = 0; i <= MaxClients; i++) {
		if (!IsFakeClient(i) && g_Enabled) {
			if (g_PlayerDbId[i] > 0 && g_PlayerSpawnedAt[i] > 0) {
				decl String:Sql[SQL_MAX_LENGTH];
				Format(Sql, sizeof(Sql), SQL_UPDATE_TIMEALIVE, RoundToZero(GetClientTime(i)) - g_PlayerSpawnedAt[i], g_PlayerDbId[i], g_ServerID);
				SQL_TQuery(g_db, SQL_LogError, Sql);
			}
			g_PlayerSpawnedAt[i] = 0;
		}
	}
}

/**
 * Event Handler for PlayerDeath
 */
public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast) {
	if (!g_Warmup && g_Enabled && g_db) {
		new victimId = GetEventInt(event, "userid");
		new attackerId = GetEventInt(event, "attacker");
		new assistId = GetEventInt(event, "assist");
		new weaponIdx = GetEventInt(event, "weapon_index");
		new bool:headshot = GetEventBool(event, "headshot");
		decl String:weaponName[65];
		GetEventString(event, "weapon", weaponName, sizeof(weaponName));
		
#if defined DEBUG
		decl String:msg[255];
		Format(msg, sizeof(msg), "*** Event_PlayerDeath ***: userid=%d, attacker=%d, assist=%d, headshot=%d, weapon_index=%d, weapon='%s'",  
			victimId, attackerId, assistId, headshot, weaponIdx, weaponName);
		LogMessage(msg);
#endif
		
		// reset victim's killstreak
		decl String:Sql[SQL_MAX_LENGTH];
		victimId = GetClientOfUserId(victimId);
		attackerId = GetClientOfUserId(attackerId);
		assistId = GetClientOfUserId(assistId);
#if defined DEBUG
		Format(msg, sizeof(msg), "*** Event_PlayerDeath ***: user database id=%d, attacker database id=%d",  
			g_PlayerDbId[victimId], g_PlayerDbId[attackerId]);
		LogMessage(msg);
#endif		
		if (g_PlayerDbId[victimId] > 0) {
			g_PlayerKillstreak[victimId] = 0;
			// increase victim's death counter, store time alive and substract points
			new penaltyPoints = g_PointsPerDeath;
			new ungraceful = 0;
			if (weaponIdx == -1 || victimId == attackerId) {
				// probably ungraceful death
				penaltyPoints = g_PointsPerUngracefulDeath;
				ungraceful = 1;
			}
			new timeAlive = RoundToZero(GetClientTime(victimId)) - g_PlayerSpawnedAt[victimId];
			g_PlayerSpawnedAt[victimId] = 0;
			g_PlayerPoints[victimId] += penaltyPoints;
			Format(Sql, sizeof(Sql), SQL_UPDATE_DEATHS_POINTS, ungraceful, penaltyPoints, timeAlive, g_PlayerDbId[victimId], g_ServerID);
			SQL_TQuery(g_db, SQL_LogError, Sql);
			// tell victim about his/her misery (in case there are points to loose)
			if (penaltyPoints != 0 && g_InformAboutPoints)
				if (ungraceful > 0)
					if (penaltyPoints != 1)
						PrintToChat(victimId, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_RED, "UngracefulDeathMessage", -penaltyPoints);
					else
						PrintToChat(victimId, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_RED, "UngracefulDeathMessageSingular");
				else {
					if (penaltyPoints != 1)
						PrintToChat(victimId, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_RED, "DeathMessage", -penaltyPoints);
					else
						PrintToChat(victimId, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_RED, "DeathMessageSingular");
				}
		}
		if (g_PlayerDbId[attackerId] > 0 && victimId != attackerId) {
			// find the weapon data and give points to attacker
			new rankPoints = GetKillPointsToWeaponIdx(weaponIdx, !headshot, weaponName);
			decl headshotInc;
			if (headshot)
				headshotInc = 1;
			else
				headshotInc = 0;
			DB_Format_SQL_INSERT_WEAPONSTAT_KILLS(g_SQLite, Sql, sizeof(Sql), g_PlayerDbId[attackerId], g_ServerID, weaponIdx, headshotInc);
#if defined DEBUG
			PrintToServer("%sSQL_INSERT_WEAPONSTAT_KILLS: %s", PLUGIN_LOGPREFIX, Sql);
#endif
			SQL_TQuery(g_db, SQL_LogError, Sql);
			g_PlayerPoints[attackerId] += rankPoints;
			Format(Sql, sizeof(Sql), SQL_UPDATE_POINTS, rankPoints, g_PlayerDbId[attackerId], g_ServerID);
#if defined DEBUG
			PrintToServer("%sSQL_UPDATE_POINTS: %s", PLUGIN_LOGPREFIX, Sql);
#endif
			SQL_TQuery(g_db, SQL_LogError, Sql);
			// increase attacker's killstreak
			g_PlayerKillstreak[attackerId]++;
			if (g_PlayerKillstreak[attackerId] > g_PlayerMaxKillstreak[attackerId]) {
				// new personal killstreak record: store it!
				g_PlayerMaxKillstreak[attackerId] = g_PlayerKillstreak[attackerId];
				Format(Sql, sizeof(Sql), SQL_UPDATE_KILLSTREAK, g_PlayerMaxKillstreak[attackerId], g_PlayerDbId[attackerId], g_ServerID);
#if defined DEBUG
				PrintToServer("%sSQL_UPDATE_KILLSTREAK: %s", PLUGIN_LOGPREFIX, Sql);
#endif
				SQL_TQuery(g_db, SQL_LogError, Sql);
			}
			// tell attacker about his/her fortune
			if (g_InformAboutPoints) {
				decl String:victimName[MAX_NAME_LENGTH];
				GetClientName(victimId, victimName, sizeof(victimName));
				if (headshot)
					if (rankPoints != 1)
						PrintToChat(attackerId, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_TEAM, "HeadshotMessage", rankPoints, victimName);
					else
						PrintToChat(attackerId, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_TEAM, "HeadshotMessageSingular", victimName);
				else
					if (rankPoints != 1)
						PrintToChat(attackerId, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_TEAM, "KillMessage", rankPoints, victimName);
					else
						PrintToChat(attackerId, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_TEAM, "KillMessageSingular", victimName);
			}
		}
		if (g_PlayerDbId[assistId] > 0 && g_PointsPerAssist != 0) {
			// credit points to assisting player
			g_PlayerPoints[assistId] += g_PointsPerAssist;
			Format(Sql, sizeof(Sql), SQL_UPDATE_POINTS, g_PointsPerAssist, g_PlayerDbId[assistId], g_ServerID);
			SQL_TQuery(g_db, SQL_LogError, Sql);
			// increase kill assists counter
			Format(Sql, sizeof(Sql), SQL_UPDATE_KILLASSISTS, g_PlayerDbId[assistId], g_ServerID);
			SQL_TQuery(g_db, SQL_LogError, Sql);
			// tell assisting player about his/her fortune
			if (g_InformAboutPoints) {
				if (g_PointsPerAssist == 1)
					PrintToChat(assistId, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_TEAM, "AssistMessageSingular", g_PointsPerAssist);
				else
					PrintToChat(assistId, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_TEAM, "AssistMessagePlural", g_PointsPerAssist);
			}
		}
		if (g_PlayerDbId[attackerId] > 0 && g_PlayerDbId[victimId] > 0) {
			// write kill log
			DB_Format_SQL_INSERT_KILLLOG(g_SQLite, Sql, sizeof(Sql), g_PlayerDbId[attackerId], g_ServerID, g_PlayerDbId[victimId]);
			SQL_TQuery(g_db, SQL_LogError, Sql);
		}
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
	
	if (g_Enabled) {
		decl String:strStartFrom[20];
		new startFrom = 0;
		if (args >= 1) {
			// starting number specified, get it
			GetCmdArg(1, strStartFrom, sizeof(strStartFrom));
			startFrom = StringToInt(strStartFrom);
			if (startFrom < 1) {
				decl String:strCommand[MAX_NAME_LENGTH];
				GetCmdArg(0, strCommand, sizeof(strCommand));
				ReplyToCommand(client, "%t", "CommandReplyTop10", strCommand);
				return Plugin_Handled;
			} else
				startFrom--;
		}
		if (client == 0) {
			// this command cannot be issued from the console
			ReplyToCommand(client, "%t", "CommandReplyFromConsole");
		} else
			InitRankList(client, startFrom, 1);
	}
 	return Plugin_Handled;
}

/**
 * Initializes the ranking list for a given client
 * This routine is esp. needed to get back from a ranking data panel
 * ...I did not find a more elegant way... :-(
 *
 * @param client 		client id
 * @param startFrom		start the ranking list from this position
 * @displayItem			menu pagination will make sure that this item is on the panel
 *
 * @noreturn
 */
void InitRankList(const client, const int startFrom, const int displayItem) {
	if (client <= MaxClients)
		if (IsClientConnected(client) && !IsFakeClient(client)) {
			g_CurrentMenuState[client][0] = startFrom;
			g_CurrentMenuState[client][1] = displayItem - 1;
			decl String:Sql[SQL_MAX_LENGTH];
		 	Format(Sql, sizeof(Sql), SQL_SELECT_TOP10, GetTime() - g_MaxIdleSecs, startFrom, 500);
		 	SQL_TQuery(g_db, SQL_ShowRanklist, Sql, GetClientUserId(client));
		 }
}

/**
 * Handler for displaying the ranking list
 */
public SQL_ShowRanklist(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	new client = GetClientFromUserID(data, hndl, error);
	if (client > 0) {
		decl String:menuLine[MAX_NAME_LENGTH + 30];
		Menu menu = new Menu(RanklistMenuHandler);
		Format(menuLine, sizeof(menuLine), "%T", "RanklistTitle", client, g_ActivePlayers);
		menu.SetTitle(menuLine);
		new i = 1;
		decl String:playerName[MAX_NAME_LENGTH];
		decl playerId;
		decl String:item[3 * 8 + 1];
		decl playerPoints;
		while (SQL_FetchRow(hndl)) {
			SQL_FetchString(hndl, 0, playerName, MAX_NAME_LENGTH);
			playerId = SQL_FetchInt(hndl, 1);
			playerPoints = SQL_FetchInt(hndl, 2);
			Format(menuLine, sizeof(menuLine), "%T", "RanklistLine", client, i + g_CurrentMenuState[client][0], playerName, playerPoints);
			// somehow clumsy way to pass information to the menu handler: store player id, rank and startFrom in item as hex string
			Format(item, sizeof(item), "%08x%08x%08x", playerId, i, g_CurrentMenuState[client][0]);
			menu.AddItem(item, menuLine);
			i++;
		}
		menu.ExitButton = true;
		menu.DisplayAt(client, (g_CurrentMenuState[client][1] / 7) * 7, 30);
		return;
	}
}

/**
 * Handler for ranking list inputs
 */
public RanklistMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	// If an option was selected, init the player panel
	if (action == MenuAction_Select) {
		new String:info[3 * 8 + 1];
		GetMenuItem(menu, param2, info, sizeof(info));
		if (strlen(info) == 3 * 8) {
			new startFrom = StringToInt(info[2 * 8], 16);
			info[2 * 8] = 0;
			new itemNo = StringToInt(info[8], 16);
			info[8] = 0;
			new playerId = StringToInt(info, 16);
			// store information about coming from ranklist - to get back after closing the ranking panel
			g_CurrentMenuState[param1][0] = startFrom;
			g_CurrentMenuState[param1][1] = itemNo;
			decl String:Sql[SQL_MAX_LENGTH];
			Format(Sql, sizeof(Sql), SQL_SELECT_PLAYERSSTATS, itemNo + startFrom, playerId);
#if defined DEBUG
			PrintToServer("%sRanklistMenuHandler: %s", PLUGIN_LOGPREFIX, Sql);
#endif
			SQL_TQuery(g_db, SQL_InitRankingPanel, Sql, GetClientUserId(param1));
		}
	} else 
		if (action == MenuAction_End)
			delete menu;
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
		// Level 1 = default and global values
		if (strcmp(key, "PointsPerDeath", false) == 0) {
			intVal = StringToInt(value);
			if (intVal >= -999 && intVal <= 999) {
				g_PointsPerDeath = intVal;
			} else {
				result = Config_ReplyToParseErrorInt(key, value, -999, 999);
			}
		} else if (strcmp(key, "PointsPerUngracefulDeath", false) == 0) {
			intVal = StringToInt(value);
			if (intVal >= -999 && intVal <= 999) {
				g_PointsPerUngracefulDeath = intVal;
			} else {
				result = Config_ReplyToParseErrorInt(key, value, -999, 999);
			}
		} else if (strcmp(key, "PointsPerKill", false) == 0) {
			intVal = StringToInt(value);
			if (intVal >= -999 && intVal <= 999) {
				g_DefaultPointsPerKill = intVal;
			} else {
				result = Config_ReplyToParseErrorInt(key, value, -999, 999);
			}
		} else if (strcmp(key, "PointsPerAssist", false) == 0) {
			intVal = StringToInt(value);
			if (intVal >= -999 && intVal <= 999) {
				g_PointsPerAssist = intVal;
			} else {
				result = Config_ReplyToParseErrorInt(key, value, -999, 999);
			}
		} else if (strcmp(key, "PointsPerHeadshot", false) == 0) {
			intVal = StringToInt(value);
			if (intVal >= -999 && intVal <= 999) {
				g_DefaultPointsPerHeadshot = intVal;
			} else {
				result = Config_ReplyToParseErrorInt(key, value, -999, 999);
			}
		} else if (strcmp(key, "ServerID", false) == 0) {
			intVal = StringToInt(value);
			if (intVal >= 0 && intVal <= 999) {
				g_ServerID = intVal;
			} else {
				result = Config_ReplyToParseErrorInt(key, value, 0, 999);
			}
		} else if (strcmp(key, "MaxIdleDays", false) == 0) {
			intVal = StringToInt(value);
			if (intVal >= 0 && intVal <= 9999) {
				g_MaxIdleSecs = intVal * 24 * 60 * 60;
			} else {
				result = Config_ReplyToParseErrorInt(key, value, 0, 9999);
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
				result = Config_ReplyToParseErrorInt(key, value, -999, 999);
			}
		} else if (strcmp(key, "PointsPerHeadshot", false) == 0) {
			intVal = StringToInt(value);
			if (intVal >= -999 && intVal <= 999) {
				g_currentWeaponConfig[cs_PointsPerHeadshot] = intVal;
			} else {
				result = Config_ReplyToParseErrorInt(key, value, -999, 999);
			}
		}
	}
	return result;
}

/*
 * Internal routine for reacting to errors in config files
 */
SMCResult:Config_ReplyToParseErrorInt(const String:key[], const String:value[], const minValue, const maxValue) {
	Format(g_LastError, sizeof(g_LastError), "Error in config file line %d: Invalid value specified for '%s': %s (value must be between %d and %d)", 
		g_ConfigLine, key, value, minValue, maxValue);
	LogError(g_LastError);
	return SMCParse_Halt;
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
	// check for teamplay map and start warmup timer
	if ((g_CvarFofWarmupTime != INVALID_HANDLE) && (g_CvarFofCurrentMode != INVALID_HANDLE)) {
		new mode = GetConVarInt(g_CvarFofCurrentMode);
		new warmupSecs = GetConVarInt(g_CvarFofWarmupTime);
		if ((mode == 1 || mode == 2) && warmupSecs > 0) {
			// we have to start a warmup timer!
			g_Warmup = true;
			CreateTimer(float(warmupSecs), Timer_WarmupEnded);
		} else
			g_Warmup = false;
	} else
		g_Warmup = false;
	// reset flag for round summary timer
	g_RoundTimer = false;
}

/**
 * Handler for the timer to end the warmup time 
 * 
 * @param timer 		handle for the timer
 */
public Action:Timer_WarmupEnded(Handle:timer, any:data) {
	// now end the warmup time
	g_Warmup = false;
#if defined DEBUG
	SayToDeveloper(">>>>> Warmup time ended now!");
#endif
	return Plugin_Stop;
}

/**
 * Handler for the timer present a round summary 
 * 
 * @param timer 		handle for the timer
 */
public Action:Timer_RoundSummary(Handle:timer, any:data) {
	
	decl timeleft;
	GetMapTimeLeft(timeleft);
#if defined DEBUG
	PrintToServer(">>>>> Round summary starting! Time left: %d", timeleft);
#endif
	if (g_RoundSummary) {
		// initiate round summaries - transform players ids to a string
		decl String:playerIds[MAXPLAYERS * 12];
		IntToString(-1, playerIds, sizeof(playerIds));
		decl offset;
		for (new i = 1; i < MaxClients; i++)
			if (IsClientConnected(i) && !IsFakeClient(i) && g_PlayerDbId[i] > 0) {
				offset = strlen(playerIds);
				Format(playerIds[offset], sizeof(playerIds) - offset - 12, ",%d", g_PlayerDbId[i]);
			}
		// collect current players ranks
		decl String:Sql[SQL_MAX_LENGTH];
		DB_Format_SQL_SELECT_RANKS(g_SQLite, Sql, sizeof(Sql), GetTime() - g_MaxIdleSecs, playerIds);
		SQL_TQuery(g_db, SQL_TellRoundSummary, Sql);
		return Plugin_Stop;
	} else
		return Plugin_Continue;
}


/**
 * Callback after executing SQL / got players rank, now present the round summary
 */
public void SQL_TellRoundSummary(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl != INVALID_HANDLE && strlen(error) == 0) {
		decl i;
		decl playerId;
		decl rank;
		while (SQL_FetchRow(hndl)) {
			playerId = SQL_FetchInt(hndl, 0);
			rank = SQL_FetchInt(hndl, 1);
			for (i = 1; i < sizeof(g_PlayerRankAtRoundstart); i++) {
				if (g_PlayerDbId[i] == playerId && IsClientConnected(i) && !IsFakeClient(i)) {
					// display summary to player
					if (g_PlayerPointsAtRoundstart[i] > g_PlayerPoints[i]) {
						// player has lost points
						PrintToChat(i, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_NORM, "RoundSummaryPointsLost", 
								CHAT_COLORTAG_GOLD, CHAT_COLORTAG_NORM, 
								g_PlayerPointsAtRoundstart[i] - g_PlayerPoints[i], g_PlayerPoints[i],
								CHAT_COLORTAG_RED, CHAT_COLORTAG_NORM,
								CHAT_COLORTAG_GOLD, CHAT_COLORTAG_NORM);
					} else {
						// player has earned points (or at least did not loose them)
						PrintToChat(i, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_NORM, "RoundSummaryPointsGained", 
								CHAT_COLORTAG_GOLD, CHAT_COLORTAG_NORM, 
								g_PlayerPoints[i] - g_PlayerPointsAtRoundstart[i], g_PlayerPoints[i],
								CHAT_COLORTAG_TEAM, CHAT_COLORTAG_NORM,
								CHAT_COLORTAG_GOLD, CHAT_COLORTAG_NORM);
					}
					if (g_PlayerRankAtRoundstart[i] < rank) {
						// player has dismounted
						PrintToChat(i, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_NORM, "RoundSummaryRankedDown", 
								CHAT_COLORTAG_GOLD, CHAT_COLORTAG_NORM, 
								rank - g_PlayerRankAtRoundstart[i], rank,
								CHAT_COLORTAG_RED, CHAT_COLORTAG_NORM,
								CHAT_COLORTAG_TEAM, CHAT_COLORTAG_NORM);
					} else if (g_PlayerRankAtRoundstart[i] > rank) {
						// player has climbed up
						PrintToChat(i, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_NORM, "RoundSummaryRankedUp", 
								CHAT_COLORTAG_GOLD, CHAT_COLORTAG_NORM, 
								g_PlayerRankAtRoundstart[i] - rank, rank,
								CHAT_COLORTAG_TEAM, CHAT_COLORTAG_NORM,
								CHAT_COLORTAG_TEAM, CHAT_COLORTAG_NORM);
					} else {
						// player stayed where he/she was
						PrintToChat(i, "%s%t%s%t", CHAT_COLORTAG1, "ChatPrefix", CHAT_COLORTAG_NORM, "RoundSummaryRankKept", 
								CHAT_COLORTAG_GOLD, CHAT_COLORTAG_NORM, 
								rank,
								CHAT_COLORTAG_TEAM, CHAT_COLORTAG_NORM);
					}
					break;
				}
			}
		}
	} else if (strlen(error) > 0)
		LogError("SQL error occured: %s", error);
}



/**
 * Handler for all commands that can affect more than one target.
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

	if (strcmp(strTarget, COMMAND_GIVEPOINTS, false) == 0) {
		commandType = 1;
		if (args != 2) {
			ReplyToCommand(client, "%t", "CommandReplyGivePoints", strTarget, strTarget);
			return Plugin_Handled;
		}
	} else 
		commandType = 0;
	
	if (args >= 1)
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
					// COMMAND_GIVEPOINTS
					decl points;
					if (param2[0] == '=') {
						// set points to a certain value
						points = StringToInt(param2[1]);
						commandType = 0;
					} else
						// increase or decrease points
						points = StringToInt(param2);
					new minPoints = -999999;
					new maxPoints = 999999;
					if (points == 0 || points < minPoints || points > maxPoints) {
						ReplyToCommand(client, "%t", "CommandReplyGivePoints2", minPoints, maxPoints);
					} else {
						// now do it
						GetClientName(targetList[i], strTarget, sizeof(strTarget));
						if (g_PlayerDbId[targetList[i]] > 0) {
							decl String:Sql[SQL_MAX_LENGTH];
							if (commandType == 0)
								Format(Sql, sizeof(Sql), SQL_UPDATE_POINTS_ABSOLUTE, points, g_PlayerDbId[targetList[i]], g_ServerID);
							else
								Format(Sql, sizeof(Sql), SQL_UPDATE_POINTS, points, g_PlayerDbId[targetList[i]], g_ServerID);
							SQL_TQuery(g_db, SQL_LogError, Sql);
							if (commandType == 0)
								ReplyToCommand(client, "%t", "CommandResultGivePointsAbs", strTarget, points);
							else
								if (points < 0)
									ReplyToCommand(client, "%t", "CommandResultGivePointsDec", strTarget, -points);
								else
									ReplyToCommand(client, "%t", "CommandResultGivePointsInc", strTarget, points);
						} else
							ReplyToCommand(client, "%t", "CommandReplyGivePoints3", strTarget);
					}
				}
			}
		}
	}
	return Plugin_Handled;
}

/**
 * Handler for sm_rank command
 * 
 * @param client 	client id
 * @args			Arguments given for the command
 *
 */
public Action:RankCommandHandler(client, args) {
	if (client == 0) {
		// this command cannot be issued from the console
		ReplyToCommand(client, "%t", "CommandReplyFromConsole");
		return Plugin_Handled;
	}
	if (IsClientConnected(client) && !IsFakeClient(client)) {
		// show round summary
		decl String:playerIds[12];
		IntToString(g_PlayerDbId[client], playerIds, sizeof(playerIds));
		decl String:Sql[SQL_MAX_LENGTH];
		DB_Format_SQL_SELECT_RANKS(g_SQLite, Sql, sizeof(Sql), GetTime() - g_MaxIdleSecs, playerIds);
		SQL_TQuery(g_db, SQL_TellRoundSummary, Sql);
	}
	// initiate rank panel
	return InitRankCommand(client, args);
}

/**
 * Initializes the rank panel as a command
 * 
 * @param client 	client id
 * @args			Arguments given for the command
 * @databaseid		if set, this players database id will be shown
 *
 */
Action:InitRankCommand(client, args, databaseid = -1) {
	if (g_Enabled) {
		decl String:strTarget[MAX_NAME_LENGTH];
		new showPlayerId = g_PlayerDbId[client];
		if (args >= 1) {
			// target specified, get client id
			GetCmdArg(1, strTarget, sizeof(strTarget));
			// target @me doesn't work because ProcessTargetString is performed server side - so replace it!
			if (strcmp(strTarget, "@me", false) == 0)
				Format(strTarget, sizeof(strTarget), "#%d", GetClientUserId(client));
			// analyse target string
			new String:targetName[MAX_TARGET_LENGTH];
			decl targetList[MAXPLAYERS + 1];
			decl targetCount;
			new bool:tn_is_ml;
			if ((targetCount = ProcessTargetString(
				strTarget, 
				0, 
				targetList, 
				MAXPLAYERS, 
				COMMAND_FILTER_CONNECTED + COMMAND_FILTER_NO_BOTS, 
				targetName, 
				sizeof(targetName), 
				tn_is_ml)) <= 0) {
					// TODO: check if target is a name, then search for it
				ReplyToTargetError(client, targetCount);
				return Plugin_Handled;
			} else 
				showPlayerId = g_PlayerDbId[targetList[0]];
		}
		if (databaseid > 0)
			showPlayerId = databaseid;
		else
			g_CurrentMenuState[client][0] = -1;
		if (showPlayerId > 0 && IsClientConnected(client)) {
			decl String:Sql[SQL_MAX_LENGTH];
			Format(Sql, sizeof(Sql), SQL_SELECT_PLAYERSRANK2, showPlayerId, GetTime() - g_MaxIdleSecs, showPlayerId);
			SQL_TQuery(g_db, SQL_GotRankForStatisticsPanel, Sql, GetClientUserId(client));
		}
	}
	return Plugin_Handled;
}

/**
 * Callback after executing SQL / got player id and rank for intitializing a ranking statistics panel
 */
public void SQL_GotRankForStatisticsPanel(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	new client = GetClientFromUserID(data, hndl, error);
	if (client > 0) {
		new showPlayerId = 0;
		new rank = -1;
		if (SQL_FetchRow(hndl)) {
			showPlayerId = SQL_FetchInt(hndl, 0);
			rank = SQL_FetchInt(hndl, 1);
		}
		//g_CurrentMenuState[client][0] = -1;
		decl String:Sql[SQL_MAX_LENGTH];
		Format(Sql, sizeof(Sql), SQL_SELECT_PLAYERSSTATS, rank, showPlayerId);
#if defined DEBUG
		PrintToServer("%s\n*** Get Player Stats: %s\n", PLUGIN_LOGPREFIX, Sql);
#endif		
		SQL_TQuery(g_db, SQL_InitRankingPanel, Sql, data);
	}
}

/**
 * Callback after executing SQL / got player rank and stats - now init the panel!
 */
public void SQL_InitRankingPanel(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	new client = GetClientFromUserID(data, hndl, error);
	if (client > 0) {
		if (SQL_FetchRow(hndl)) {
			decl String:playerName[MAX_NAME_LENGTH];
			SQL_FetchString(hndl, 1, playerName, MAX_NAME_LENGTH);
			new kills = SQL_FetchInt(hndl, 4);
			new deaths = SQL_FetchInt(hndl, 8);
			g_CurrentStatsPlayerId[client] = SQL_FetchInt(hndl, 0);
			new timeSinceSpawn = RoundToZero(GetClientTime(client)) - g_PlayerSpawnedAt[client];
			new timeAlive = SQL_FetchInt(hndl, 10) + timeSinceSpawn;
			new spawns = SQL_FetchInt(hndl, 11);
			
			decl String:panelLine[MAX_PANELLINE_LENGTH];
			Panel panel = new Panel();
			// check if this is the spawn welcome message
			if (timeSinceSpawn < 10)
				Format(panelLine, sizeof(panelLine), "%T", "RankPanel_WelcomeTitle", client, playerName);
			else
				Format(panelLine, sizeof(panelLine), "%T", "RankPanel_Title", client, playerName);
			panel.SetTitle(panelLine);
			panel.DrawItem("", ITEMDRAW_SPACER | ITEMDRAW_RAWLINE);
			Format(panelLine, sizeof(panelLine), "%T", "RankPanel_Line1", client, SQL_FetchInt(hndl, 2), g_ActivePlayers);
			panel.DrawText(panelLine);
			Format(panelLine, sizeof(panelLine), "%T", "RankPanel_Line2", client, SQL_FetchInt(hndl, 3));
			panel.DrawText(panelLine);
			Format(panelLine, sizeof(panelLine), "%T", "RankPanel_Line3", client, kills, SQL_FetchInt(hndl, 5));
			panel.DrawText(panelLine);
			Format(panelLine, sizeof(panelLine), "%T", "RankPanel_Line4", client, SQL_FetchInt(hndl, 6));
			panel.DrawText(panelLine);
			Format(panelLine, sizeof(panelLine), "%T", "RankPanel_Line5", client, SQL_FetchInt(hndl, 7));
			panel.DrawText(panelLine);
			Format(panelLine, sizeof(panelLine), "%T", "RankPanel_Line6", client, deaths, SQL_FetchInt(hndl, 9));
			panel.DrawText(panelLine);
			panel.DrawItem("", ITEMDRAW_SPACER | ITEMDRAW_RAWLINE);
			if (timeAlive > 0) {
				Format(panelLine, sizeof(panelLine), "%T", "RankPanel_Line7", client, timeAlive / (60 * 60), (timeAlive / 60) % 60);
				panel.DrawText(panelLine);
			}
			if (timeAlive > 0) {
				timeAlive = timeAlive / spawns;
				Format(panelLine, sizeof(panelLine), "%T", "RankPanel_Line8", client, timeAlive / 60, timeAlive % 60);
				panel.DrawText(panelLine);
			}
			float kdRatio = 999.99;
			if (deaths != 0)
				kdRatio = FloatDiv(float(kills), float(deaths));
			Format(panelLine, sizeof(panelLine), "%T", "RankPanel_Line9", client, kdRatio);
			panel.DrawText(panelLine);
			panel.DrawItem("", ITEMDRAW_SPACER | ITEMDRAW_RAWLINE);
			if (g_PlayerDbId[client] == SQL_FetchInt(hndl, 0)) {
				// player watches her/his own statistics
				Format(panelLine, sizeof(panelLine), "%T", "RankPanel_ShowKillers", client);
				panel.DrawItem(panelLine);
				Format(panelLine, sizeof(panelLine), "%T", "RankPanel_ShowVictims", client);
				panel.DrawItem(panelLine);
			} else {
				// player watches statistics of somebody else
				Format(panelLine, sizeof(panelLine), "%T", "RankPanel_ShowKillers3rd", client);
				panel.DrawItem(panelLine);
				Format(panelLine, sizeof(panelLine), "%T", "RankPanel_ShowVictims3rd", client);
				panel.DrawItem(panelLine);
			}
			for (new i = 1; i <= 7; i++)
				panel.DrawItem("", ITEMDRAW_NOTEXT);
			Format(panelLine, sizeof(panelLine), "%T", "Close", client);
			panel.DrawItem(panelLine, ITEMDRAW_CONTROL);
			panel.Send(client, RankingPanelHandler, 30);
			delete panel;
		}
	}
}

/**
 * Handler for ranking panel events - restore ranking list menu, if applicable
 */
public int RankingPanelHandler(Menu menu, MenuAction action, int param1, int param2)
{
#if defined DEBUG
	PrintToServer("%s*** RankingPanelHandler *** action: %d, param1: %d, param2: %d / g_CurrentMenuState: %d", PLUGIN_LOGPREFIX, action, param1, param2, g_CurrentMenuState[param1][0]);
#endif
	if (action == MenuAction_Select) {
		decl String:Sql[SQL_MAX_LENGTH];
		if (g_CurrentStatsPlayerId[param1] > 0) {
			if (param2 == 1) {
				// show killer list
				Format(Sql, sizeof(Sql), SQL_SELECT_KILLERS, g_CurrentStatsPlayerId[param1], GetTime() - g_MaxIdleSecs, KILLER_LIST_ITEMS);
#if defined DEBUG
				PrintToServer("%s*** RankingPanelHandler *** - SQL_SELECT_KILLERS: %s", PLUGIN_LOGPREFIX, Sql);
#endif

				SQL_TQuery(g_db, SQL_InitKillersPanel, Sql, GetClientUserId(param1));
			} else if (param2 == 2) {
				// show victim list
				Format(Sql, sizeof(Sql), SQL_SELECT_VICTIMS, g_CurrentStatsPlayerId[param1], GetTime() - g_MaxIdleSecs, KILLER_LIST_ITEMS);
				SQL_TQuery(g_db, SQL_InitVictimsPanel, Sql, GetClientUserId(param1));
			} else if (param2 == 10) {
				if (g_CurrentMenuState[param1][0] >= 0)
					InitRankList(param1, g_CurrentMenuState[param1][0], g_CurrentMenuState[param1][1]);
			}
		} else if (action == MenuAction_Cancel || action == MenuAction_End)
			if (g_CurrentMenuState[param1][0] >= 0)
				InitRankList(param1, g_CurrentMenuState[param1][0], g_CurrentMenuState[param1][1]);
	}
}


/**
 * Callback after executing SQL / got the list of the killers!
 */
public void SQL_InitKillersPanel(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	new client = GetClientFromUserID(data, hndl, error);
	if (client > 0) {
		decl String:playerName[MAX_NAME_LENGTH];
		decl String:panelLine[MAX_PANELLINE_LENGTH];
		Panel panel = new Panel();
		new i = 1;
		while (SQL_FetchRow(hndl) && i <= KILLER_LIST_ITEMS) {
			if (i == 1) {
				SQL_FetchString(hndl, 2, playerName, MAX_NAME_LENGTH);
				Format(panelLine, sizeof(panelLine), "%T", "KillerlistTitle", client, playerName);
				panel.SetTitle(panelLine);
				panel.DrawItem("", ITEMDRAW_SPACER | ITEMDRAW_RAWLINE);
			}		
			SQL_FetchString(hndl, 0, playerName, MAX_NAME_LENGTH);
			Format(panelLine, sizeof(panelLine), "%T", "KillerlistLine", client, i, playerName, SQL_FetchInt(hndl, 1));
			panel.DrawText(panelLine);
			i++;
		}
		if (i == 1) {
			Format(panelLine, sizeof(panelLine), "%T", "KillerlistLine_empty", client);
			panel.DrawText(panelLine);
		}
		panel.DrawItem("", ITEMDRAW_SPACER | ITEMDRAW_RAWLINE);
		for (i = 1; i <= 9; i++)
			panel.DrawItem("", ITEMDRAW_NOTEXT);
		Format(panelLine, sizeof(panelLine), "%T", "Close", client);
		panel.DrawItem(panelLine, ITEMDRAW_CONTROL);
		panel.Send(client, RankingSubpanelHandler, 30);
		delete panel;
	}
}

/**
 * Callback after executing SQL / got the list of the victims!
 */
public void SQL_InitVictimsPanel(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	new client = GetClientFromUserID(data, hndl, error);
	if (client > 0) {
		decl String:playerName[MAX_NAME_LENGTH];
		decl String:panelLine[MAX_PANELLINE_LENGTH];
		Panel panel = new Panel();
		new i = 1;
		while (SQL_FetchRow(hndl) && i <= KILLER_LIST_ITEMS) {
			if (i == 1) {
				SQL_FetchString(hndl, 2, playerName, MAX_NAME_LENGTH);
				Format(panelLine, sizeof(panelLine), "%T", "VictimlistTitle", client, playerName);
				panel.SetTitle(panelLine);
				panel.DrawItem("", ITEMDRAW_SPACER | ITEMDRAW_RAWLINE);
			}		
			SQL_FetchString(hndl, 0, playerName, MAX_NAME_LENGTH);
			Format(panelLine, sizeof(panelLine), "%T", "VictimlistLine", client, i, playerName, SQL_FetchInt(hndl, 1));
			panel.DrawText(panelLine);
			i++;
		}
		if (i == 1) {
			Format(panelLine, sizeof(panelLine), "%T", "VictimlistLine_empty", client);
			panel.DrawText(panelLine);
		}
		panel.DrawItem("", ITEMDRAW_SPACER | ITEMDRAW_RAWLINE);
		for (i = 1; i <= 9; i++)
			panel.DrawItem("", ITEMDRAW_NOTEXT);
		Format(panelLine, sizeof(panelLine), "%T", "Back", client);
		panel.DrawItem(panelLine, ITEMDRAW_CONTROL);
		panel.Send(client, RankingSubpanelHandler, 30);
		delete panel;
	}
}

/**
 * Handler for ranking subpanels: go back to ranking panel
 */
public int RankingSubpanelHandler(Menu menu, MenuAction action, int param1, int param2)
{
#if defined DEBUG
	PrintToServer("%s*** RankingSubpanelHandler *** action: %d, param1: %d, param2: %d, dbid: %d", PLUGIN_LOGPREFIX, action, param1, param2, g_CurrentStatsPlayerId[param1]);
#endif
	if (g_CurrentStatsPlayerId[param1] > 0) {
		// fake issuing a rank command with db id as parameter
		InitRankCommand(param1, 0, g_CurrentStatsPlayerId[param1]);
	}
}
 
/**
 * Callback after executing SQL / got the top 3 for the explanation panel!
 */
public void SQL_InitExplanationPanel(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	new client = GetClientFromUserID(data, hndl, error);
	if (client > 0) {
		decl String:playerName[MAX_NAME_LENGTH];
		GetClientName(client, playerName, sizeof(playerName));
		// SQL_FetchString(hndl, 0, playerName, MAX_NAME_LENGTH);
		
		decl String:panelLine[MAX_PANELLINE_LENGTH];
		Panel panel = new Panel();
		Format(panelLine, sizeof(panelLine), "%T", "ExplainPanel_WelcomeTitle", client, playerName);
		panel.SetTitle(panelLine);
		panel.DrawItem("", ITEMDRAW_SPACER | ITEMDRAW_RAWLINE);
		Format(panelLine, sizeof(panelLine), "%T", "ExplainPanel_Line1", client, g_ActivePlayers);
		panel.DrawText(panelLine);
		panel.DrawItem("", ITEMDRAW_SPACER | ITEMDRAW_RAWLINE);
		Format(panelLine, sizeof(panelLine), "%T", "ExplainPanel_Line2", client);
		panel.DrawText(panelLine);
		panel.DrawItem("", ITEMDRAW_SPACER | ITEMDRAW_RAWLINE);
		new i = 1;
		while (SQL_FetchRow(hndl)) {
			SQL_FetchString(hndl, 0, playerName, MAX_NAME_LENGTH);
			Format(panelLine, sizeof(panelLine), "%T", "ExplainPanel_Rankline", client, i, playerName, SQL_FetchInt(hndl, 2));
			panel.DrawText(panelLine);
			i++;
		}
		panel.DrawItem("", ITEMDRAW_SPACER | ITEMDRAW_RAWLINE);
		new String:command[50] = COMMAND_TOP10;
		Format(panelLine, sizeof(panelLine), "%T", "ExplainPanel_Line3", client, command[3]);
		panel.DrawText(panelLine);
		Format(panelLine, sizeof(panelLine), "%T", "ExplainPanel_Line4", client, command[3]);
		panel.DrawText(panelLine);
		strcopy(command, sizeof(command), COMMAND_RANK);
		Format(panelLine, sizeof(panelLine), "%T", "ExplainPanel_Line5", client, command[3]);
		panel.DrawText(panelLine);
		Format(panelLine, sizeof(panelLine), "%T", "ExplainPanel_Line6", client, command[3]);
		panel.DrawText(panelLine);
		panel.DrawItem("", ITEMDRAW_SPACER | ITEMDRAW_RAWLINE);
		Format(panelLine, sizeof(panelLine), "%T", "Close", client);
		panel.DrawItem(panelLine, ITEMDRAW_CONTROL);
		panel.Send(client, EmptyPanelHandler, 30);
		delete panel;
	}
}

/**
 * Handler for panel events - nothing to do here...
 */
public int EmptyPanelHandler(Menu menu, MenuAction action, int param1, int param2)
{
	// really?
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
	PrintToChat(client, "%sWarmup: %d, AnnouncePlayer: %d, ShowPanels: %d, InformPoints: %d, Enabled: %d",
		PLUGIN_LOGPREFIX, g_Warmup, g_AnnouncePlayers, g_ShowPanels, g_InformAboutPoints, g_Enabled);
	PrintToChat(client, "\x01\\x01 \x02\\x02 \x03\\x03 \x04\\x04 \x05\\x05 \x06\\x06");
	return Plugin_Handled;
}
#endif

//
// Private functions
//


/** 
 * Finds the correct kill or headshot points to a given weapon idx.
 * Sets the correct values directly in rankPoints or headshotPoints.
 *
 * @param client				client id
 * @param getKillPoints			true to receive kill points, false to receive headshot points 
 * @return
 */
GetKillPointsToWeaponIdx(const weaponIdx, const bool:getKillPoints, const String:weaponName[]) {
	new max = GetArraySize(g_WeaponDetails);
	new thisWC[enumConfigWeaponDetails];
	decl points;
	new bool:found = false;
	if (getKillPoints) 
		points = g_DefaultPointsPerKill;
	else
		points = g_DefaultPointsPerHeadshot;
	for (new i = 0; i < max; i++) {
		GetArrayArray(g_WeaponDetails, i, thisWC[0]);
		if (thisWC[cs_WeaponIdx] == weaponIdx) {
			found = true;
			if (getKillPoints) 
				points = thisWC[cs_PointsPerKill];
			else
				points = thisWC[cs_PointsPerHeadshot];
			break;
		}
	}
	if (!found) {
		// unknown weapon index - log this!
		LogMessage("%sWarning: Weapon index %i ('%s') has not been found in config file.", PLUGIN_LOGPREFIX, weaponIdx, weaponName);
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
			g_PlayerSpawnedAt[i] = 0;
			g_PlayerMaxKillstreak[i] = -1;
			g_PlayerDbId[i] = -1;
			g_PlayerPreviousLogin[i] = -1;
			g_PlayerSilentInit[i] = false;
			g_PlayerPointsAtRoundstart[i] = 0;
			g_PlayerPoints[i] = 0;
			g_PlayerRankAtRoundstart[i] = 0;
		}
	} else if (client >= 0 && client < sizeof(g_PlayerKillstreak)) {
		g_PlayerKillstreak[client] = 0;
		g_PlayerSpawnedAt[client] = 0;
		g_PlayerMaxKillstreak[client] = -1;
		g_PlayerDbId[client] = -1;
		g_PlayerPreviousLogin[client] = -1;
		g_PlayerSilentInit[client] = false;
		g_PlayerPointsAtRoundstart[client] = 0;
		g_PlayerPoints[client] = 0;
		g_PlayerRankAtRoundstart[client] = 0;
	}
}

//
// Database functions
//

/**
 * Open database or create it if needed
 */
bool:SQL_OpenDB() {
	new bool:Result = false;
	g_DBInit = false;
	if (SQL_CheckConfig(SQL_DBNAME))
		SQL_TConnect(SQL_Connected, SQL_DBNAME);
	else {
		// no database config specified - use sqlite version
		g_SQLite = true;
		new Handle:kv;
		kv = CreateKeyValues("");
		DB_SetConnectionKV(kv);
		g_db = SQL_ConnectCustom(kv, g_LastError, sizeof(g_LastError), false);
		CloseHandle(kv);		
		
		if (g_db == INVALID_HANDLE)
			LogMessage("%sFailed to connect to sqlite database '%s': %s", PLUGIN_LOGPREFIX, SQL_DBNAME, g_LastError);
		else {
			LogMessage("%sSucessfully connected to sqlite database '%s'", PLUGIN_LOGPREFIX, SQL_DBNAME);
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
		LogMessage("%sFailed to connect to database '%s': %s", PLUGIN_LOGPREFIX, SQL_DBNAME, error);
		SetFailState("%sCould not reach database '%s'! Error: %s", PLUGIN_LOGPREFIX, SQL_DBNAME, error);
		g_DBInit = true;
		return;
	} else {
		// Determine db engine
		Database db = view_as<Database>(hndl);
		DBDriver driver = db.Driver;
		decl String:DBEngine[10];
		driver.GetProduct(DBEngine, sizeof(DBEngine));
		g_SQLite = (strcmp(DBEngine, "SQLite") == 0);
#if defined DEBUG
		PrintToServer("%s*** SQL_Connected ***: Flag SQLite: %d, db engine: %s", PLUGIN_LOGPREFIX, g_SQLite, DBEngine);
#endif
		LogMessage("%sSucessfully connected to %s database '%s'", PLUGIN_LOGPREFIX, DBEngine, SQL_DBNAME);
		g_db = hndl;
		SQL_InitDB();
		g_DBInit = true;
		// Check if we need to init some clients (due to race conditions)
		if (g_ClientsToInit != INVALID_HANDLE) {
			new arraySize = GetArraySize(g_ClientsToInit);
			while (arraySize > 0) {
				OnClientPostAdminCheck(GetArrayCell(g_ClientsToInit, arraySize - 1));
				RemoveFromArray(g_ClientsToInit, arraySize - 1);
				arraySize -= 1;
			}
		}			
	}
}

/**
 * Initialize database; also handle schema updates
 */
void SQL_InitDB() {
 	
	if (g_db != INVALID_HANDLE) {
		// This is only the basic schema version, for updates view routine SQL_CheckVersion further down
		SQL_LockDatabase(g_db);
		DB_Create_Tbl_Players(g_db, g_SQLite);
		DB_Create_Tbl_PlayersStats(g_db, g_SQLite);
		DB_Create_Tbl_Servers(g_db, g_SQLite);
		DB_Create_Tbl_Version(g_db, g_SQLite);
		DB_Create_Tbl_WeaponStats(g_db, g_SQLite);
		DB_Create_Idx_Players(g_db, g_SQLite);
		DB_Create_Idx_Players_1(g_db, g_SQLite);
		DB_Create_Idx_Players_2(g_db, g_SQLite);
		DB_Create_Idx_Players_3(g_db, g_SQLite);
		SQL_UnlockDatabase(g_db);
		// Check schema version and apply changes
		SQL_TQuery(g_db, SQL_CheckVersion, SQL_SELECT_SCHEMAVERSION);
	}
}

/**
 * Callback after executing SQL: Check schema version
 */
public void SQL_CheckVersion(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl != INVALID_HANDLE && strlen(error) == 0) {
		new version = 1;
		if (SQL_FetchRow(hndl)) {
			version = SQL_FetchInt(hndl, 0);
		}
		SQL_LockDatabase(g_db);
		if (version < 2) {
			DB_Create_Tbl_KillLog(g_db, g_SQLite);
			DB_Create_Idx_KillLog_1(g_db, g_SQLite);
		}
		if (version < 3) {
			DB_Update_3_1(g_db, g_SQLite);
			DB_Update_3_2(g_db, g_SQLite);
			DB_Update_3_3(g_db, g_SQLite);
			DB_Update_3_4(g_db, g_SQLite);
			DB_Update_3_5(g_db, g_SQLite);
			DB_Update_3_6(g_db, g_SQLite);
		}
		if (version < 4) {
			DB_Update_3_1(g_db, g_SQLite);
			DB_Update_3_2(g_db, g_SQLite);
			DB_Update_4_3(g_db, g_SQLite);
			DB_Update_4_4(g_db, g_SQLite);
			DB_Update_3_5(g_db, g_SQLite);
			DB_Update_3_6(g_db, g_SQLite);
			DB_Cleanup(g_db, g_SQLite);
			SQL_UnlockDatabase(g_db);
			// Save latest schema version
			decl String:Sql[SQL_MAX_LENGTH];
			Format(Sql, sizeof(Sql), SQL_INSERT_SCHEMAVERSION, 4);
			SQL_FastQuery(g_db, Sql);
		} else
			SQL_UnlockDatabase(g_db);
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

#if defined DEBUG
/**
 * Say something to almostagreatcoder!
 */
void SayToDeveloper(const String:msg[]) {
	decl String:playerName[MAX_NAME_LENGTH];
	for (new i = 1; i <= MaxClients; i++) {
		if (IsClientConnected(i) && !IsFakeClient(i)) {
			GetClientName(i, playerName, sizeof(playerName));
			if (strcmp(playerName, "almostagreatplayer", false) == 0)
				PrintToChat(i, msg);
		}	
	}
}
#endif
