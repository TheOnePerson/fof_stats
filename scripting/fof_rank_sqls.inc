/*
 * Include containing all database related sql resources
 */
#if defined _FOF_SQL_included
	#endinput
#endif
#define _FOF_SQL_included

#define SQL_DBNAME "fofstats"
#define SQL_MAX_LENGTH 8192

/**
 * This routine is only used whenthe database engine is sqlite and there needs to be a 
 * database created. MYSQL engine needs a proper config section in databases.cfg!
 */
 stock void DB_SetConnectionKV(Handle:kv) {
	KvSetString(kv, "driver", "sqlite");
	KvSetString(kv, "database", SQL_DBNAME);
}

stock void DB_Create_Tbl_Players(const Handle:db, const bool:sqlite) {
	if (sqlite) {
		SQL_FastQuery(db, "CREATE TABLE IF NOT EXISTS \"Players\" (  \
			\"ID\"  INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,  \
			\"Name\"  TEXT NOT NULL DEFAULT '',  \
			\"SteamID\"  TEXT NOT NULL,  \
			\"IP\"  TEXT NOT NULL DEFAULT ''  \
			);");
	} else {
		SQL_FastQuery(db, "CREATE TABLE IF NOT EXISTS `Players` (  \
			`ID`  INTEGER PRIMARY KEY AUTO_INCREMENT NOT NULL,  \
			`Name`  VARCHAR(200) NOT NULL,  \
			`SteamID`  VARCHAR(60) NOT NULL,  \
			`IP`  VARCHAR(50) NOT NULL DEFAULT ''  \
			);");
	}
}

stock void DB_Create_Idx_Players(const Handle:db, const bool:sqlite) {
	if (sqlite) {
		SQL_FastQuery(db, "CREATE UNIQUE INDEX IF NOT EXISTS \"IDX_SteamID\" ON \"Players\" (\"SteamID\" ASC);");
	} else {
		SQL_FastQuery(db, "ALTER TABLE `Players` ADD UNIQUE INDEX `IDX_SteamID`(`SteamID` ASC);");
	}
}

stock void DB_Create_Tbl_PlayersStats(const Handle:db, const bool:sqlite) {
	SQL_FastQuery(db, "CREATE TABLE IF NOT EXISTS PlayerStats ( \
		PlayerID  INTEGER NOT NULL,  \
		ServerID  INTEGER NOT NULL,  \
		Logins  INTEGER NOT NULL DEFAULT 0,  \
		Points  INTEGER NOT NULL DEFAULT 0,  \
		Spawns  INTEGER NOT NULL DEFAULT 0,  \
		Deaths  INTEGER NOT NULL DEFAULT 0,  \
		UngracefulDeaths  INTEGER NOT NULL DEFAULT 0,  \
		Killstreak  INTEGER NOT NULL DEFAULT 0,  \
		KillAssists  INTEGER NOT NULL DEFAULT 0,  \
		TimeAlive  INTEGER NOT NULL DEFAULT 0,  \
		Firstenter  INTEGER NOT NULL DEFAULT 0,  \
		Lastenter  INTEGER NOT NULL DEFAULT 0,  \
		PRIMARY KEY (PlayerID ASC, ServerID ASC)  \
		);");
}

stock void DB_Create_Idx_Players_1(const Handle:db, const bool:sqlite) {
	if (sqlite) {
		SQL_FastQuery(db, "CREATE INDEX IF NOT EXISTS \"IDX_PlayerStats_Points\" ON \"PlayerStats\" (\"Points\" ASC);");
	} else {
		SQL_FastQuery(db, "ALTER TABLE `PlayerStats` ADD INDEX `IDX_PlayerStats_Points`(`Points` ASC);");
	}
}

stock void DB_Create_Idx_Players_2(const Handle:db, const bool:sqlite) {
	if (sqlite) {
		SQL_FastQuery(db, "CREATE INDEX IF NOT EXISTS \"IDX_PlayerStats_Killstreak\" ON \"PlayerStats\" (\"Killstreak\" ASC);");
	} else {
		SQL_FastQuery(db, "ALTER TABLE `PlayerStats` ADD INDEX `IDX_PlayerStats_Killstreak`(`Killstreak` ASC);");
	}
}

stock void DB_Create_Idx_Players_3(const Handle:db, const bool:sqlite) {
	if (sqlite) {
		SQL_FastQuery(db, "CREATE INDEX IF NOT EXISTS \"IDX_PlayerStats_Lastenter\" ON \"PlayerStats\" (\"Lastenter\" ASC);");
	} else {
		SQL_FastQuery(db, "ALTER TABLE `PlayerStats` ADD INDEX `IDX_PlayerStats_Lastenter`(`Lastenter` ASC);");
	}
}

stock void DB_Create_Tbl_Servers(const Handle:db, const bool:sqlite) {
	if (sqlite) {
		SQL_FastQuery(db, "CREATE TABLE IF NOT EXISTS \"Servers\" (  \
			\"ID\"  INTEGER NOT NULL,  \
			\"Name\"  TEXT NOT NULL,  \
			\"SteamAppID\"  INTEGER NOT NULL DEFAULT 0,  \
			PRIMARY KEY (\"ID\" ASC) \
			);");
	} else {
		SQL_FastQuery(db, "CREATE TABLE IF NOT EXISTS `Servers` (  \
			`ID`  INTEGER NOT NULL,  \
			`Name`  VARCHAR(50) NOT NULL,  \
			`SteamAppID`  INTEGER NOT NULL DEFAULT 0,  \
			PRIMARY KEY (`ID` ASC) \
			);");
	}
}
	
stock void DB_Create_Tbl_Version(const Handle:db, const bool:sqlite) {
	SQL_FastQuery(db, "CREATE TABLE IF NOT EXISTS Version (  \
		SchemaVersion  INTEGER NOT NULL DEFAULT 0  \
		);");
}
	
stock void DB_Create_Tbl_WeaponStats(const Handle:db, const bool:sqlite) {
	if (sqlite) {
		SQL_FastQuery(db, "CREATE TABLE IF NOT EXISTS \"WeaponStats\" (  \
			\"ServerID\"  INTEGER NOT NULL, \
			\"PlayerID\"  INTEGER NOT NULL, \
			\"WeaponIdx\"  INTEGER NOT NULL, \
			\"Kills\"  INTEGER NOT NULL DEFAULT 0, \
			\"Headshots\"  INTEGER NOT NULL DEFAULT 0, \
			PRIMARY KEY (\"ServerID\", \"PlayerID\", \"WeaponIdx\") \
			);");
	} else {
		SQL_FastQuery(db, "CREATE TABLE IF NOT EXISTS `WeaponStats` (  \
			`ServerID`  INTEGER NOT NULL, \
			`PlayerID`  INTEGER NOT NULL, \
			`WeaponIdx`  INTEGER NOT NULL, \
			`Kills`  INTEGER NOT NULL DEFAULT 0, \
			`Headshots`  INTEGER NOT NULL DEFAULT 0, \
			INDEX `IDX_WeaponStats_PlayerID`(PlayerID), \
			PRIMARY KEY (`ServerID`, `PlayerID`, `WeaponIdx`) \
			);");
	}
}

stock void DB_Create_Tbl_KillLog(const Handle:db, const bool:sqlite) {
	SQL_FastQuery(db, "CREATE TABLE IF NOT EXISTS KillLog ( \
		ServerID  INTEGER NOT NULL, \
		KillerID  INTEGER NOT NULL, \
		VictimID  INTEGER NOT NULL, \
		WeaponIdx  INTEGER NOT NULL, \
		Time  INTEGER NOT NULL DEFAULT 0, \
		PRIMARY KEY (KillerID, Time, ServerID) \
		);");
}

#define SQL_SELECT_SCHEMAVERSION "SELECT MAX(SchemaVersion) FROM Version;"

#define SQL_INSERT_SCHEMAVERSION "INSERT INTO Version(SchemaVersion) VALUES (%d);"

stock void DB_Create_Idx_KillLog_1(const Handle:db, const bool:sqlite) {
	if (sqlite) {
		SQL_FastQuery(db, "CREATE INDEX IF NOT EXISTS \"IDX_KillLog_Victim\" ON \"KillLog\" (\"VictimID\", \"Time\", \"ServerID\");");
	} else {
		SQL_FastQuery(db, "ALTER TABLE `KillLog` ADD INDEX `IDX_KillLog_Victim`(`VictimID`, `Time`, `ServerID`);");
	}
}

stock void DB_Format_SQL_INSERT_PLAYER(const bool:sqlite, String:Sql[], int maxlen, const String:steamID[], const String:playerNameEsc[], const String:playerIp[]) {
	if (sqlite) {
		Format(Sql, maxlen, "INSERT OR REPLACE INTO Players(ID, Name, SteamID, IP) \
			VALUES ((SELECT ID FROM Players WHERE SteamID = '%s'), '%s', '%s', '%s');", steamID, playerNameEsc, steamID, playerIp);
	} else {
		Format(Sql, maxlen, "INSERT INTO Players(Name, SteamID, IP) \
			VALUES ('%s', '%s', '%s') \
			ON DUPLICATE KEY UPDATE Name = '%s', SteamID = '%s', IP = '%s';", playerNameEsc, steamID, playerIp, playerNameEsc, steamID, playerIp);
	}
}

#define SQL_SELECT_PLAYERID "SELECT ID FROM Players WHERE SteamID = '%s' LIMIT 1;"

stock void DB_Format_SQL_INSERT_PLAYERSTAT(const bool:sqlite, String:Sql[], int maxlen, const int playerID, const int serverID, const int loginInc) {
	if (sqlite) {
		Format(Sql, maxlen, "INSERT OR REPLACE INTO PlayerStats(PlayerID, ServerID, Logins, Points, Spawns, Deaths, UngracefulDeaths, Killstreak, KillAssists, TimeAlive, Firstenter, Lastenter) \
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
			);", playerID, serverID,
				playerID, serverID, loginInc,
				playerID, serverID,
				playerID, serverID,
				playerID, serverID,
				playerID, serverID,
				playerID, serverID,
				playerID, serverID,
				playerID, serverID,
				playerID, serverID, GetTime(), 
				playerID, serverID);
	} else {
		Format(Sql, maxlen, "INSERT INTO PlayerStats(PlayerID, ServerID, Logins, Firstenter) \ 
			VALUES (%d, %d, 1, %d) \
    		ON DUPLICATE KEY UPDATE Logins = Logins + %d;", playerID, serverID, GetTime(), loginInc);
	}
}

#define SQL_SELECT_MAXKILLSTREAK "SELECT MAX(Killstreak) FROM PlayerStats WHERE PlayerID = %i;"

#define SQL_SELECT_DATAONCONNECT "SELECT SUM(S1.Points) TotalPoints, MAX(CASE S1.ServerID WHEN %d THEN S1.Lastenter ELSE 0 END) AS LatestEnter, \
	(SELECT COUNT(PlayerID) FROM (SELECT S2.PlayerID FROM PlayerStats AS S2 WHERE S2.Lastenter > %d AND S2.Spawns > 0 \
		GROUP BY S2.PlayerID HAVING SUM(S2.Points) > (SELECT SUM(S3.Points) FROM PlayerStats AS S3 WHERE S3.PlayerID = %i)) AS BP1) AS BetterPlayers, \
	(SELECT COUNT(*) FROM PlayerStats WHERE Lastenter > %d AND Spawns > 0) AS AllPlayers \
	FROM PlayerStats AS S1 WHERE S1.PlayerID = %i;"

#define SQL_UPDATE_LASTENTER "UPDATE PlayerStats SET Lastenter = %d WHERE PlayerID = %d and ServerID = %d;"

// This SQL seems a bit complicated, but it covers multiserver functionality!
#define SQL_SELECT_PLAYERSRANK2 "SELECT %i, COUNT(PlayerID) FROM (SELECT PlayerID FROM PlayerStats WHERE Lastenter > %d AND Spawns > 0 \
	GROUP BY PlayerID HAVING SUM(Points) > (SELECT SUM(Points) FROM PlayerStats WHERE PlayerID = %i)) AS Num"

#define SQL_SELECT_TOTALPLAYERS "SELECT COUNT(DISTINCT p.ID) FROM Players AS p INNER JOIN PlayerStats AS s ON s.PlayerID = p.ID \
	WHERE s.Lastenter > %d AND s.Spawns > 0;"

#define SQL_UPDATE_SPAWNS "UPDATE PlayerStats SET Spawns = Spawns + 1 WHERE PlayerID = %d AND ServerID = %d;"

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

stock void DB_Format_SQL_INSERT_WEAPONSTAT_KILLS(const bool:sqlite, String:Sql[], int maxlen, const int playerID, const int serverID, const int weaponIdx, const int headshotInc) {
	if (sqlite) {
		Format(Sql, maxlen, "INSERT OR REPLACE INTO WeaponStats(ServerID, PlayerID, WeaponIdx, Kills, Headshots) \
			VALUES (%d, %d, %d, COALESCE((SELECT Kills FROM WeaponStats WHERE ServerID = %d and PlayerID = %d and WeaponIdx = %d) + 1, 1), \
			COALESCE((SELECT Headshots FROM WeaponStats WHERE ServerID = %d and PlayerID = %d and WeaponIdx = %d) + %d, %d) \
			);", serverID, playerID, weaponIdx, 
			serverID, playerID, weaponIdx,
			serverID, playerID, weaponIdx, headshotInc, headshotInc);
	} else {
		Format(Sql, maxlen, "INSERT INTO WeaponStats(ServerID, PlayerID, WeaponIdx, Kills, Headshots) \
			VALUES (%d, %d, %d, 1, %d) \
    		ON DUPLICATE KEY UPDATE Kills = Kills + 1, Headshots = Headshots + %d;", serverID, playerID, weaponIdx, headshotInc, headshotInc);
	}
}

stock void DB_Format_SQL_INSERT_KILLLOG(const bool:sqlite, String:Sql[], int maxlen, const int playerID, const int serverID, const int victimID) {
	if (sqlite) {
		Format(Sql, maxlen, "INSERT OR REPLACE INTO KillLog(ServerID, KillerID, VictimID, Kills) \
			VALUES (%d, %d, %d, \
			COALESCE((SELECT Kills FROM KillLog WHERE ServerID = %d and KillerID = %d and VictimID = %d) + 1, 1));", serverID, playerID, victimID);
	} else {
		Format(Sql, maxlen, "INSERT INTO KillLog(ServerID, KillerID, VictimID, Kills) \
			VALUES (%d, %d, %d, 1) \
			ON DUPLICATE KEY UPDATE Kills = Kills + 1;", serverID, playerID, victimID);
	}
}

#define SQL_SELECT_TOP10 "SELECT Name, p.ID, SUM(Points) FROM Players AS p INNER JOIN PlayerStats AS s ON s.PlayerID = p.ID \
	 WHERE s.Lastenter > %d AND s.Spawns > 0 GROUP BY p.ID ORDER BY SUM(Points) DESC, SUM(TimeAlive) DESC, SUM(Logins) LIMIT %d, %d;"

#define SQL_SELECT_PLAYERSSTATS "SELECT p.ID, p.Name, %i, \
	SUM(s.Points), COALESCE((SELECT SUM(w.Kills) FROM WeaponStats w WHERE w.PlayerID = p.ID), 0) Kills, \
	COALESCE((SELECT SUM(w.Headshots) FROM WeaponStats w WHERE w.PlayerID = p.ID), 0) Headshots, \
	SUM(s.KillAssists) Assists, MAX(s.Killstreak) Streak, \
	SUM(s.Deaths) Deaths, SUM(s.UngracefulDeaths) Ungraceful, SUM(s.TimeAlive), SUM(s.Spawns) Spawns \
	FROM Players p INNER JOIN PlayerStats s ON s.PlayerID = p.ID \
	WHERE p.ID =  %i GROUP BY p.ID;"

#define SQL_SELECT_KILLERS "SELECT p.Name, SUM(Kills), p2.Name \
	FROM KillLog AS k \
	INNER JOIN Players AS p ON p.ID = k.KillerID \
	INNER JOIN PlayerStats AS s ON p.ID = s.PlayerID \
	INNER JOIN Players AS p2 ON p2.ID = k.VictimID \
	WHERE VictimID = %d \
	GROUP BY k.KillerID \
	HAVING MAX(s.Lastenter) > %d AND SUM(s.Spawns) > 0 \
	ORDER BY SUM(Kills) DESC, k.KillerID \
	LIMIT %d;"

#define SQL_SELECT_VICTIMS "SELECT p.Name, SUM(Kills), p2.Name \
	FROM KillLog AS k \
	INNER JOIN Players AS p ON p.ID = k.VictimID \
	INNER JOIN PlayerStats AS s ON p.ID = s.PlayerID \
	INNER JOIN Players AS p2 ON p2.ID = k.KillerID \
	WHERE KillerID = %d \
	GROUP BY k.VictimID \
	HAVING MAX(s.Lastenter) > %d AND SUM(s.Spawns) > 0 \
	ORDER BY SUM(Kills) DESC, k.VictimID \
	LIMIT %d;"

stock void DB_Format_SQL_SELECT_RANKS(const bool:sqlite, String:Sql[], const int maxlen, const int timeLimit, const String:playerIDs[]) {
	if (sqlite) {
		Format(Sql, maxlen, "SELECT s1.PlayerID, \
			(SELECT COUNT(PlayerID) FROM (SELECT PlayerID FROM PlayerStats WHERE Lastenter > %d AND Spawns > 0 \
				GROUP BY PlayerID HAVING SUM(Points) > (SELECT SUM(Points) FROM PlayerStats WHERE PlayerID = s1.PlayerID))) \
			FROM PlayerStats AS s1 WHERE PlayerID IN (%s);", timeLimit, playerIDs);
	} else {
		Format(Sql, maxlen, "SELECT  \
			PlayerID,  \
		    (SELECT  \
				COUNT(s2.PlayerID)  \
				FROM (SELECT  \
						s3.PlayerID,  \
			            SUM(s3.Points) AS Points  \
						FROM PlayerStats AS s3  \
						WHERE s3.Lastenter > %d AND s3.Spawns > 0  \
			            GROUP BY s3.PlayerID  \
					) AS s2  \
		        WHERE s2.Points > q1.SumPoints  \
			) AS Rank  \
			FROM (SELECT   \
					s1.PlayerID,  \
					SUM(s1.Points) AS SumPoints  \
				FROM PlayerStats AS s1  \
				WHERE s1.PlayerID IN (%s)  \
				GROUP BY s1.PlayerID  \
			) AS q1  \
			GROUP BY q1.PlayerID;", timeLimit, playerIDs);
	}
}

stock void DB_Update_3_1(const Handle:db, const bool:sqlite) {
	SQL_FastQuery(db, "ALTER TABLE KillLog RENAME TO _KillLog_old_temp;");
}

stock void DB_Update_3_2(const Handle:db, const bool:sqlite) {
	if (sqlite) {
		SQL_FastQuery(db, "DROP INDEX \"IDX_KillLog_Victim\";");
	} else {
		SQL_FastQuery(db, "ALTER TABLE `_KillLog_old_temp` DROP INDEX `IDX_KillLog_Victim`;");
	}
}

stock void DB_Update_3_3(const Handle:db, const bool:sqlite) {
	SQL_FastQuery(db, "CREATE TABLE IF NOT EXISTS KillLog ( \
		ServerID  INTEGER NOT NULL, \
		KillerID  INTEGER NOT NULL, \
		VictimID  INTEGER NOT NULL, \
		WeaponIdx  INTEGER NOT NULL, \
		Kills  INTEGER NOT NULL DEFAULT 0, \
		PRIMARY KEY (ServerID ASC, KillerID ASC, VictimID, WeaponIdx));");
}

stock void DB_Update_3_4(const Handle:db, const bool:sqlite) {
	SQL_FastQuery(db, "INSERT INTO KillLog (ServerID, KillerID, VictimID, WeaponIdx, Kills) \
		SELECT ServerID, KillerID, VictimID, WeaponIdx, COUNT(*) \
		FROM _KillLog_old_temp \
		GROUP BY ServerID, KillerID, VictimID, WeaponIdx \
		ORDER BY ServerID, KillerID, VictimID, WeaponIdx;");
}

stock void DB_Update_3_5(const Handle:db, const bool:sqlite) {
	if (sqlite) {
		SQL_FastQuery(db, "CREATE INDEX \"IDX_KillLog_Victim\" ON \"KillLog\" (\"VictimID\" ASC, \"KillerID\" ASC);");
	} else {
		SQL_FastQuery(db, "ALTER TABLE `KillLog` ADD INDEX `IDX_KillLog_Victim` (`VictimID` ASC, `KillerID` ASC);");
	}
}

stock void DB_Update_3_6(const Handle:db, const bool:sqlite) {
	SQL_FastQuery(db, "DROP TABLE _KillLog_old_temp;");
}

stock void DB_Update_4_3(const Handle:db, const bool:sqlite) {
	SQL_FastQuery(db, "CREATE TABLE IF NOT EXISTS KillLog ( \
		ServerID  INTEGER NOT NULL, \
		KillerID  INTEGER NOT NULL, \
		VictimID  INTEGER NOT NULL, \
		Kills  INTEGER NOT NULL DEFAULT 0, \
		PRIMARY KEY (KillerID ASC, ServerID ASC, VictimID));");
}

stock void DB_Update_4_4(const Handle:db, const bool:sqlite) {
	SQL_FastQuery(db, "INSERT INTO KillLog (ServerID, KillerID, VictimID, Kills) \
	SELECT ServerID, KillerID, VictimID, SUM(Kills) \
	FROM _KillLog_old_temp \
	GROUP BY ServerID, KillerID, VictimID \
	ORDER BY KillerID, ServerID, VictimID;");
}

stock void DB_Cleanup(const Handle:db, const bool:sqlite) {
	if (sqlite) {
		SQL_FastQuery(db, "VACUUM;");
	} else {
		SQL_FastQuery(db, "OPTIMIZE_TABLE `KillLog`, `Players`, `PlayerStats`, `WeaponStats`, `Servers`, `Version`;");
	}
}

