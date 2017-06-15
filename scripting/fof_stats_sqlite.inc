/*
 * Include containing all database related sql resources: SQlite version
 */
#if defined _FOF_SQLITE_included
	#endinput
#endif
#define _FOF_SQLITE_included

#define SQL_DEFAULTDBNAME "fofstats"
#define SQL_DBTYPE "SQLite"
#define SQL_DBDRIVERNAME "sqlite"
#define SQL_MAX_LENGTH 8192

#define SQL_CREATE_TBL_Players "CREATE TABLE \"Players\" (  \
	\"ID\"  INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,  \
	\"Name\"  TEXT NOT NULL DEFAULT '',  \
	\"SteamID\"  TEXT NOT NULL,  \
	\"IP\"  TEXT NOT NULL DEFAULT ''  \
	);"
#define SQL_CREATE_TBL_Players_Idx	"CREATE UNIQUE INDEX \"IDX_SteamID\"  \
	ON \"Players\" (\"SteamID\" ASC);"

#define SQL_CREATE_TBL_PlayerStats "CREATE TABLE \"PlayerStats\" ( \
	\"PlayerID\"  INTEGER NOT NULL,  \
	\"ServerID\"  INTEGER NOT NULL,  \
	\"Logins\"  INTEGER NOT NULL DEFAULT 0,  \
	\"Points\"  INTEGER NOT NULL DEFAULT 0,  \
	\"Deaths\"  INTEGER NOT NULL DEFAULT 0,  \
	\"UngratefulDeaths\"  INTEGER NOT NULL DEFAULT 0,  \
	\"Killstreak\"  INTEGER NOT NULL DEFAULT 0,  \
	\"KillAssists\"  INTEGER NOT NULL DEFAULT 0,  \
	\"TimeAlive\"  INTEGER NOT NULL DEFAULT 0,  \
	\"Firstenter\"  INTEGER NOT NULL DEFAULT 0,  \
	\"Lastenter\"  INTEGER NOT NULL DEFAULT 0,  \
	PRIMARY KEY (\"PlayerID\" ASC, \"ServerID\" ASC)  \
	);"

#define SQL_CREATE_TBL_PlayerStats_Idx1 "CREATE INDEX \"main\".\"IDX_PlayerStats_Points\" ON \"PlayerStats\" (\"Points\" ASC);"

#define SQL_CREATE_TBL_PlayerStats_Idx2 "CREATE INDEX \"main\".\"IDX_PlayerStats_Killstreak\" ON \"PlayerStats\" (\"Killstreak\" ASC);"

#define SQL_CREATE_TBL_Servers "CREATE TABLE \"Servers\" (  \
	\"ID\"  INTEGER NOT NULL,  \
	\"Name\"  TEXT NOT NULL,  \
	\"SteamAppID\"  INTEGER NOT NULL DEFAULT 0,  \
	PRIMARY KEY (\"ID\" ASC) \
	);"
	
#define SQL_CREATE_TBL_Version "CREATE TABLE \"Version\" (  \
	\"SchemaVersion\"  INTEGER NOT NULL DEFAULT 0  \
	);"
	
#define SQL_CREATE_TBL_WeaponStats "CREATE TABLE \"WeaponStats\" (  \
	\"ServerID\"  INTEGER NOT NULL,  \
	\"PlayerID\"  INTEGER NOT NULL,  \
	\"WeaponIdx\"  INTEGER NOT NULL,  \
	\"Kills\"  INTEGER NOT NULL DEFAULT 0,  \
	\"Headshots\"  INTEGER NOT NULL DEFAULT 0,  \
	PRIMARY KEY (\"ServerID\", \"PlayerID\", \"WeaponIdx\")  \
	);"

#define SQL_INSERT_PLAYER "INSERT OR REPLACE INTO Players(ID, Name, SteamID, IP) \
	VALUES ((SELECT ID FROM Players WHERE SteamID = '%s'), '%s', '%s', '%s');"

#define SQL_SELECT_PLAYERID "SELECT ID FROM Players WHERE SteamID = '%s'"

#define SQL_INSERT_PLAYERSTAT "INSERT OR REPLACE INTO PlayerStats(PlayerID, ServerID, Logins, Points, Deaths, UngratefulDeaths, Killstreak, KillAssists, TimeAlive, Firstenter, Lastenter) \
	VALUES (%d, %d, COALESCE((SELECT Logins FROM PlayerStats WHERE PlayerID = %d and ServerID = %d) + %d, 1), \
	(SELECT Points FROM PlayerStats WHERE PlayerID = %d and ServerID = %d), \
	(SELECT Deaths FROM PlayerStats WHERE PlayerID = %d and ServerID = %d), \
	(SELECT UngratefulDeaths FROM PlayerStats WHERE PlayerID = %d and ServerID = %d), \
	(SELECT Killstreak FROM PlayerStats WHERE PlayerID = %d and ServerID = %d), \
	(SELECT KillAssists FROM PlayerStats WHERE PlayerID = %d and ServerID = %d), \
	(SELECT TimeAlive FROM PlayerStats WHERE PlayerID = %d and ServerID = %d), \
	COALESCE((SELECT Firstenter FROM PlayerStats WHERE PlayerID = %d and ServerID = %d), %d), \
	%d \
	);"

#define SQL_SELECT_MAXKILLSTREAK "SELECT MAX(Killstreak) FROM PlayerStats WHERE PlayerID = %i"

#define SQL_SELECT_PLAYERPOINTS "SELECT SUM(Points) FROM PlayerStats WHERE PlayerID = %i"

#define SQL_SELECT_PLAYERSRANK "SELECT COUNT(PlayerID) FROM PlayerStats WHERE Points >= %i"

// This SQL seems a bit complicated, but it covers multiserver functionality!
#define SQL_SELECT_PLAYERSRANK2 "SELECT %i, COUNT(PlayerID) FROM (SELECT PlayerID FROM PlayerStats GROUP BY PlayerID \
	HAVING SUM(Points) > (SELECT SUM(Points) FROM PlayerStats WHERE PlayerID = %i))"

#define SQL_SELECT_TOTALPLAYERS "SELECT COUNT(*) FROM Players"

#define SQL_UPDATE_DEATHS_POINTS "UPDATE PlayerStats SET Deaths = Deaths + 1, \
	UngratefulDeaths = UngratefulDeaths + %d, \
	Points = Points + (%d), \
	TimeAlive = TimeAlive + (%d) \
	WHERE PlayerID = %d and ServerID = %d;"

#define SQL_UPDATE_TIMEALIVE "UPDATE PlayerStats SET TimeAlive = TimeAlive + %d WHERE PlayerID = %d and ServerID = %d;"

#define SQL_UPDATE_POINTS "UPDATE PlayerStats SET Points = Points + (%d) WHERE PlayerID = %d and ServerID = %d;"

#define SQL_UPDATE_KILLSTREAK "UPDATE PlayerStats SET Killstreak = %d WHERE PlayerID = %d and ServerID = %d;"

#define SQL_UPDATE_KILLASSISTS "UPDATE PlayerStats SET KillAssists = KillAssists + 1 WHERE PlayerID = %d and ServerID = %d;"

#define SQL_INSERT_WEAPONSTAT_KILLS "INSERT OR REPLACE INTO WeaponStats(ServerID, PlayerID, WeaponIdx, Kills, Headshots) \
	VALUES (%d, %d, %d, COALESCE((SELECT Kills FROM WeaponStats WHERE ServerID = %d and PlayerID = %d and WeaponIdx = %d) + 1, 1), \
	COALESCE((SELECT Headshots FROM WeaponStats WHERE ServerID = %d and PlayerID = %d and WeaponIdx = %d) + %d, %d) \
	);"

#define SQL_SELECT_TOP10 "SELECT Name, p.ID, SUM(Points) FROM Players AS p INNER JOIN PlayerStats AS s ON s.PlayerID = p.ID \
	GROUP BY p.ID ORDER BY SUM(Points) DESC, SUM(TimeAlive) DESC, SUM(Logins) LIMIT %d, %d;"

#define SQL_SELECT_PLAYERSSTATS "SELECT p.ID, p.Name, %i, (SELECT COUNT(*) FROM Players) TotalPlayers, SUM(s.Points), \
	COALESCE((SELECT SUM(w.Kills) FROM WeaponStats w WHERE w.PlayerID = p.ID), 0) Kills, \
	COALESCE((SELECT SUM(w.Headshots) FROM WeaponStats w WHERE w.PlayerID = p.ID), 0) Headshots, \
	SUM(s.KillAssists) Assists, MAX(s.Killstreak) Streak, \
	SUM(s.Deaths) Deaths, SUM(s.UngratefulDeaths) Ungrateful, SUM(s.TimeAlive) \
	FROM Players p INNER JOIN PlayerStats s ON s.PlayerID = p.ID \
	WHERE p.ID =  %i GROUP BY p.ID;"

