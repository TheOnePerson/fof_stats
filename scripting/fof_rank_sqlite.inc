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
#define SQL_CREATE_TBL_Players_Idx	"CREATE UNIQUE INDEX \"IDX_SteamID\" ON \"Players\" (\"SteamID\" ASC);"

#define SQL_CREATE_TBL_PlayerStats "CREATE TABLE \"PlayerStats\" ( \
	\"PlayerID\"  INTEGER NOT NULL,  \
	\"ServerID\"  INTEGER NOT NULL,  \
	\"Logins\"  INTEGER NOT NULL DEFAULT 0,  \
	\"Points\"  INTEGER NOT NULL DEFAULT 0,  \
	\"Spawns\"  INTEGER NOT NULL DEFAULT 0,  \
	\"Deaths\"  INTEGER NOT NULL DEFAULT 0,  \
	\"UngracefulDeaths\"  INTEGER NOT NULL DEFAULT 0,  \
	\"Killstreak\"  INTEGER NOT NULL DEFAULT 0,  \
	\"KillAssists\"  INTEGER NOT NULL DEFAULT 0,  \
	\"TimeAlive\"  INTEGER NOT NULL DEFAULT 0,  \
	\"Firstenter\"  INTEGER NOT NULL DEFAULT 0,  \
	\"Lastenter\"  INTEGER NOT NULL DEFAULT 0,  \
	PRIMARY KEY (\"PlayerID\" ASC, \"ServerID\" ASC)  \
	);"

#define SQL_CREATE_TBL_PlayerStats_Idx1 "CREATE INDEX \"main\".\"IDX_PlayerStats_Points\" ON \"PlayerStats\" (\"Points\" ASC);"

#define SQL_CREATE_TBL_PlayerStats_Idx2 "CREATE INDEX \"main\".\"IDX_PlayerStats_Killstreak\" ON \"PlayerStats\" (\"Killstreak\" ASC);"

#define SQL_CREATE_TBL_PlayerStats_Idx3 "CREATE INDEX \"IDX_PlayerStats_Lastenter\" ON \"PlayerStats\" (\"Lastenter\" ASC);"

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
	\"ServerID\"  INTEGER NOT NULL, \
	\"PlayerID\"  INTEGER NOT NULL, \
	\"WeaponIdx\"  INTEGER NOT NULL, \
	\"Kills\"  INTEGER NOT NULL DEFAULT 0, \
	\"Headshots\"  INTEGER NOT NULL DEFAULT 0, \
	PRIMARY KEY (\"ServerID\", \"PlayerID\", \"WeaponIdx\") \
	);"

#define SQL_CREATE_TBL_KillLog "CREATE TABLE \"KillLog\" ( \
	\"ServerID\"  INTEGER NOT NULL, \
	\"KillerID\"  INTEGER NOT NULL, \
	\"VictimID\"  INTEGER NOT NULL, \
	\"WeaponIdx\"  INTEGER NOT NULL, \
	\"Time\"  INTEGER NOT NULL DEFAULT 0, \
	PRIMARY KEY (\"KillerID\", \"Time\", \"ServerID\") \
	);"

#define SQL_CREATE_TBL_KillLog_Idx1 "CREATE INDEX \"IDX_KillLog_Victim\" ON \"KillLog\" (\"VictimID\", \"Time\", \"ServerID\");"

#define SQL_INSERT_PLAYER "INSERT OR REPLACE INTO Players(ID, Name, SteamID, IP) \
	VALUES ((SELECT ID FROM Players WHERE SteamID = '%s'), '%s', '%s', '%s');"

#define SQL_SELECT_PLAYERID "SELECT ID FROM Players WHERE SteamID = '%s' LIMIT 1;"

#define SQL_INSERT_PLAYERSTAT "INSERT OR REPLACE INTO PlayerStats(PlayerID, ServerID, Logins, Points, Spawns, Deaths, UngracefulDeaths, Killstreak, KillAssists, TimeAlive, Firstenter, Lastenter) \
	VALUES (%d, %d, COALESCE((SELECT Logins FROM PlayerStats WHERE PlayerID = %d and ServerID = %d) + %d, 1), \
	(SELECT Points FROM PlayerStats WHERE PlayerID = %d and ServerID = %d), \
	(SELECT Spawns FROM PlayerStats WHERE PlayerID = %d and ServerID = %d), \
	(SELECT Deaths FROM PlayerStats WHERE PlayerID = %d and ServerID = %d), \
	(SELECT UngracefulDeaths FROM PlayerStats WHERE PlayerID = %d and ServerID = %d), \
	(SELECT Killstreak FROM PlayerStats WHERE PlayerID = %d and ServerID = %d), \
	(SELECT KillAssists FROM PlayerStats WHERE PlayerID = %d and ServerID = %d), \
	(SELECT TimeAlive FROM PlayerStats WHERE PlayerID = %d and ServerID = %d), \
	COALESCE((SELECT Firstenter FROM PlayerStats WHERE PlayerID = %d and ServerID = %d), %d), \
	(SELECT Lastenter FROM PlayerStats WHERE PlayerID = %d and ServerID = %d) \
	);"

#define SQL_SELECT_MAXKILLSTREAK "SELECT MAX(Killstreak) FROM PlayerStats WHERE PlayerID = %i;"

#define SQL_SELECT_DATAONCONNECT "SELECT SUM(Points), MAX(CASE ServerID WHEN %d THEN Lastenter ELSE 0 END), \
	(SELECT COUNT(PlayerID) FROM (SELECT PlayerID FROM PlayerStats WHERE Lastenter > %d AND Spawns > 0 \
		GROUP BY PlayerID HAVING SUM(Points) > (SELECT SUM(Points) FROM PlayerStats WHERE PlayerID = %i))), \
	(SELECT COUNT(*) FROM Players WHERE Lastenter > %d AND Spawns > 0) \
	FROM PlayerStats WHERE PlayerID = %i;"

#define SQL_UPDATE_LASTENTER "UPDATE PlayerStats SET Lastenter = %d WHERE PlayerID = %d and ServerID = %d;"

// This SQL seems a bit complicated, but it covers multiserver functionality!
#define SQL_SELECT_PLAYERSRANK2 "SELECT %i, COUNT(PlayerID) FROM (SELECT PlayerID FROM PlayerStats WHERE Lastenter > %d AND Spawns > 0 \
	GROUP BY PlayerID HAVING SUM(Points) > (SELECT SUM(Points) FROM PlayerStats WHERE PlayerID = %i))"

#define SQL_SELECT_TOTALPLAYERS "SELECT COUNT(DISTINCT p.ID) FROM Players AS p INNER JOIN PlayerStats AS s ON s.PlayerID = p.ID \
	WHERE s.Lastenter > %d AND s.Spawns > 0;"

#define SQL_UPDATE_SPAWNS "UPDATE PlayerStats SET Spawns = Spawns + 1 WHERE PlayerID = %d and ServerID = %d;"

#define SQL_UPDATE_DEATHS_POINTS "UPDATE PlayerStats SET Deaths = Deaths + 1, \
	UngracefulDeaths = UngracefulDeaths + %d, \
	Points = Points + (%d), \
	TimeAlive = TimeAlive + (%d) \
	WHERE PlayerID = %d and ServerID = %d;"

#define SQL_UPDATE_TIMEALIVE "UPDATE PlayerStats SET TimeAlive = TimeAlive + %d WHERE PlayerID = %d and ServerID = %d;"

#define SQL_UPDATE_POINTS_ABSOLUTE "UPDATE PlayerStats Points = (%d) WHERE PlayerID = %d and ServerID = %d;"

#define SQL_UPDATE_POINTS "UPDATE PlayerStats SET Points = Points + (%d) WHERE PlayerID = %d and ServerID = %d;"

#define SQL_UPDATE_KILLSTREAK "UPDATE PlayerStats SET Killstreak = %d WHERE PlayerID = %d and ServerID = %d;"

#define SQL_UPDATE_KILLASSISTS "UPDATE PlayerStats SET KillAssists = KillAssists + 1 WHERE PlayerID = %d and ServerID = %d;"

#define SQL_INSERT_WEAPONSTAT_KILLS "INSERT OR REPLACE INTO WeaponStats(ServerID, PlayerID, WeaponIdx, Kills, Headshots) \
	VALUES (%d, %d, %d, COALESCE((SELECT Kills FROM WeaponStats WHERE ServerID = %d and PlayerID = %d and WeaponIdx = %d) + 1, 1), \
	COALESCE((SELECT Headshots FROM WeaponStats WHERE ServerID = %d and PlayerID = %d and WeaponIdx = %d) + %d, %d) \
	);"

#define SQL_INSERT_KILLLOG "INSERT OR REPLACE INTO KillLog(ServerID, KillerID, VictimID, WeaponIdx, Time) \
	VALUES (%d, %d, %d, %d, %d);"

#define SQL_SELECT_TOP10 "SELECT Name, p.ID, SUM(Points) FROM Players AS p INNER JOIN PlayerStats AS s ON s.PlayerID = p.ID \
	 WHERE s.Lastenter > %d AND s.Spawns > 0 GROUP BY p.ID ORDER BY SUM(Points) DESC, SUM(TimeAlive) DESC, SUM(Logins) LIMIT %d, %d;"

#define SQL_SELECT_PLAYERSSTATS "SELECT p.ID, p.Name, %i, \
	SUM(s.Points), COALESCE((SELECT SUM(w.Kills) FROM WeaponStats w WHERE w.PlayerID = p.ID), 0) Kills, \
	COALESCE((SELECT SUM(w.Headshots) FROM WeaponStats w WHERE w.PlayerID = p.ID), 0) Headshots, \
	SUM(s.KillAssists) Assists, MAX(s.Killstreak) Streak, \
	SUM(s.Deaths) Deaths, SUM(s.UngracefulDeaths) Ungraceful, SUM(s.TimeAlive), SUM(s.Spawns) Spawns \
	FROM Players p INNER JOIN PlayerStats s ON s.PlayerID = p.ID \
	WHERE p.ID =  %i GROUP BY p.ID;"

#define SQL_SELECT_SCHEMAVERSION "SELECT MAX(SchemaVersion) FROM Version;"

#define SQL_INSERT_SCHEMAVERSION "INSERT INTO \"Version\"(\"SchemaVersion\") VALUES (%d);"

#define SQL_SELECT_KILLERS "SELECT p.Name, count(*) \
	FROM KillLog AS k \
	INNER JOIN Players AS p ON p.ID = k.KillerID \
	WHERE VictimID = %d AND Time > %d \
	GROUP BY k.KillerID \
	ORDER BY count(*) DESC, k.KillerID \
	LIMIT %d;"

#define SQL_SELECT_VICTIMS "SELECT p.Name, count(*) \
	FROM KillLog AS k \
	INNER JOIN Players AS p ON p.ID = k.VictimID \
	WHERE KillerID = %d AND Time > %d \
	GROUP BY k.VictimID \
	ORDER BY count(*) DESC, k.VictimID \
	LIMIT %d;"

