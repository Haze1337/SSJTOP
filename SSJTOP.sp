#include <sdktools>
#include <sdkhooks>

public Plugin myinfo = 
{
	name = "SSJ TOP",
	author = "Haze",
	description = "",
	version = "1.3",
	url = "https://steamcommunity.com/id/0x134/"
}

#define BHOP_FRAMES 10
#define RANKSCOUNT 50

char gS_Text[16];
char gS_Variable[16];

Menu gM_TopMainMenu = null;
Menu gM_TopMenus[2] = null;

Database gH_SQL = null;
bool gB_MySQL = false;

char gS_MySQL_CreateTopTable[] = "CREATE TABLE IF NOT EXISTS `ssjtop` (`duck` BOOLEAN, `rank` INT, `auth` varchar(32) COLLATE utf8mb4_general_ci, `name` VARCHAR(64) COLLATE utf8mb4_general_ci, `velocity` INT, `date` INT)";
char gS_SQLITE_CreateTopTable[] = "CREATE TABLE IF NOT EXISTS `ssjtop` (`duck` BOOLEAN, `rank` INT, `auth` varchar(32), `name` VARCHAR(64), `velocity` INT, `date` INT)";
char gS_CreateJumpsTable[] = "CREATE TABLE IF NOT EXISTS `ssjtopjumps` (`duck` BOOLEAN, `rank` INT, `jump` INT, `velocity` INT, `gain` FLOAT, `efficiency` FLOAT, `sync` FLOAT, `strafes` INT)";
char gS_LoadTop[] = "SELECT * FROM ssjtop ORDER BY velocity DESC";
char gS_LoadTopJumps[] = "SELECT * FROM ssjtopjumps";
char gS_DeleteTop[] = "DELETE FROM ssjtop";
char gS_DeleteTopJumps[] = "DELETE FROM ssjtopjumps";

int gI_LastChoice[MAXPLAYERS+1];
int gI_LastButtons[MAXPLAYERS+1];
int gI_TicksOnGround[MAXPLAYERS+1];
int gI_TouchTicks[MAXPLAYERS+1];
bool gB_TouchesWall[MAXPLAYERS+1];
float gF_LastOrigin[MAXPLAYERS+1][3];
float gF_LastVel[MAXPLAYERS+1][3];

int gI_Jump[MAXPLAYERS+1];
int gI_Strafes[MAXPLAYERS+1];
int gI_StrafeTick[MAXPLAYERS+1];
int gI_SyncedTick[MAXPLAYERS+1];
float gF_RawGain[MAXPLAYERS+1];
float gF_Trajectory[MAXPLAYERS+1];
float gF_TraveledDistance[MAXPLAYERS+1][3];
float gF_AirTime[MAXPLAYERS+1];

bool gB_Duck[MAXPLAYERS+1];
bool gB_IllegalSSJ[MAXPLAYERS+1];
bool gB_DeleteMode[MAXPLAYERS+1];
bool gB_InAir[MAXPLAYERS+1];

bool gB_DebugMessages = false;

enum struct ssj_player_stats_t
{
	int iSpeed;
	float fHeight;
	float fGain;
	float fEfficiency;
	float fSync;
	int iStrafes;
	float fAirTime;
}

enum struct ssj_top_stats_t
{
	char sAuth[32];
	char sName[64];
	int iTopSpeed;
	int iTimeStamp;
	
	int iSpeed[6];
	float fGain[6];
	float fEfficiency[6];
	float fSync[6];
	int iStrafes[6];
}

ssj_player_stats_t gA_PlayerStats[MAXPLAYERS+1][6];
ssj_top_stats_t gA_TopStats[2][RANKSCOUNT];

float gF_Tickrate = 0.01;

EngineVersion gEV_Type = Engine_Unknown;

public void OnPluginStart()
{
	gEV_Type = GetEngineVersion();
	
	if(gEV_Type == Engine_CSGO)
	{
		FormatEx(gS_Text, 16, "\x01");
		FormatEx(gS_Variable, 16, "\x0B");
	}
	else if(gEV_Type == Engine_CSS)
	{
		FormatEx(gS_Text, 16, "\x07ffffff");
		FormatEx(gS_Variable, 16, "\x073498DB");
	}
	else
	{
		SetFailState("This plugin was meant to be used in CS:S and CS:GO *only*.");
	}

	RegConsoleCmd("sm_ssjtop", Command_SSJTOP, "");
	RegAdminCmd("sm_ssjtopdelete", Command_SSJTOPDelete, ADMFLAG_ROOT, "");
	
	SQL_DBConnect();
	DB_LoadTop();
	
	HookEvent("player_jump", Player_Jump);
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}
}

public Action Command_SSJTOPDelete(int client, int args)
{
	if(client == 0)
	{
		ReplyToCommand(client, "[SM] This command can only be used in-game.");
		return Plugin_Handled;
	}
	
	if(args > 0)
	{
		char buf[4];
		GetCmdArg(1, buf, sizeof(buf));
		
		int duck = StringToInt(buf);
		if(duck < 0 || duck > 1 || !strlen(buf))
		{
			SSJTOP_PrintToChat(client, "Invalid ssj type: %s (0 = noduck | 1 = duck)", buf);
			
			return Plugin_Handled;
		}
		
		char str[4];
		GetCmdArg(2, str, sizeof(str));
		int rank = StringToInt(str) - 1;
		
		if(rank < 0 || rank > RANKSCOUNT)
		{
			SSJTOP_PrintToChat(client, "Invalid rank (1 - %d)", RANKSCOUNT);
			
			return Plugin_Handled;
		}
		
		OpenDeleteMenu(client, duck, rank);
	}
	else
	{
		gB_DeleteMode[client] = true;
		gM_TopMainMenu.Display(client, MENU_TIME_FOREVER);
	}
	
	return Plugin_Handled;
}

public Action Command_SSJTOP(int client, int args)
{
	if(client != 0)
	{
		gM_TopMainMenu.Display(client, MENU_TIME_FOREVER);
		gB_DeleteMode[client] = false;
	}
	else
	{
		ReplyToCommand(client, "Rank | Name | SSJ (No Duck)");
		for(int i = 0; i < 5; i++)
		{
			if(gA_TopStats[0][i].iTopSpeed != 0)
			{
				ReplyToCommand(client, "#%d %s - %d", i+1, gA_TopStats[0][i].sName, gA_TopStats[0][i].iTopSpeed);
			}
			else
			{
				ReplyToCommand(client, "#%d No record", i+1);
			}
		}
		ReplyToCommand(client, " ");
		ReplyToCommand(client, "Rank | Name | SSJ (Duck)");
		for(int i = 0; i < 5; i++)
		{
			if(gA_TopStats[1][i].iTopSpeed != 0)
			{
				ReplyToCommand(client, "#%d %s - %d", i+1, gA_TopStats[1][i].sName, gA_TopStats[1][i].iTopSpeed);
			}
			else
			{
				ReplyToCommand(client, "#%d No record", i+1);
			}
		}
	}
	
	return Plugin_Handled;
}

public void OnMapStart()
{
	gF_Tickrate = GetTickInterval();
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_Touch, OnTouch);
}

public void OnClientDisconnect(int client)
{
	gB_DeleteMode[client] = false;
}

// Credits: Alkatraz
void SSJ_GetStats(int client, float vel[3], float angles[3])
{
	float velocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);

	gI_StrafeTick[client]++;

	float speedmulti = GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue");
	
	gF_TraveledDistance[client][0] += velocity[0] * gF_Tickrate * speedmulti;
	gF_TraveledDistance[client][1] += velocity[1] * gF_Tickrate * speedmulti;
	velocity[2] = 0.0;

	gF_Trajectory[client] += GetVectorLength(velocity) * gF_Tickrate * speedmulti;
	
	float fore[3];
	float side[3];
	GetAngleVectors(angles, fore, side, NULL_VECTOR);
	
	fore[2] = 0.0;
	NormalizeVector(fore, fore);

	side[2] = 0.0;
	NormalizeVector(side, side);

	float wishvel[3];
	float wishdir[3];
	
	for(int i = 0; i < 2; i++)
	{
		wishvel[i] = fore[i] * vel[0] + side[i] * vel[1];
	}

	float wishspeed = NormalizeVector(wishvel, wishdir);
	float maxspeed = GetEntPropFloat(client, Prop_Send, "m_flMaxspeed");

	if(maxspeed != 0.0 && wishspeed > maxspeed)
	{
		wishspeed = maxspeed;
	}
	
	if(wishspeed > 0.0)
	{
		float wishspd = (wishspeed > 30.0)? 30.0:wishspeed;
		float currentgain = GetVectorDotProduct(velocity, wishdir);
		float gaincoeff = 0.0;

		if(currentgain < 30.0)
		{
			gI_SyncedTick[client]++;
			gaincoeff = (wishspd - FloatAbs(currentgain)) / wishspd;
		}

		if(gB_TouchesWall[client] && gI_TouchTicks[client] && gaincoeff > 0.5)
		{
			gaincoeff -= 1.0;
			gaincoeff = FloatAbs(gaincoeff);
		}

		gF_RawGain[client] += gaincoeff;
	}
}

public void Player_Jump(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if(IsFakeClient(client))
	{
		return;
	}
	
	if(gI_Jump[client] > 0 && gI_StrafeTick[client] <= 0)
	{
		return;
	}

	if(gI_Jump[client] < 6)
	{
		gI_Jump[client]++;
		
		SaveStats(client);

		gI_Strafes[client] = 0;
		gF_RawGain[client] = 0.0;
		gI_StrafeTick[client] = 0;
		gI_SyncedTick[client] = 0;
		gF_Trajectory[client] = 0.0;
		gF_TraveledDistance[client] = NULL_VECTOR;
	}
	
	gF_AirTime[client] = 0.0;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3])
{
	if(!IsPlayerAlive(client) || IsFakeClient(client))
	{
		return Plugin_Continue;
	}
	
	if((GetEntityFlags(client) & FL_ONGROUND) > 0)
	{
		if(gI_TicksOnGround[client]++ > BHOP_FRAMES)
		{
			gI_Jump[client] = 0;
			gI_Strafes[client] = 0;
			gI_StrafeTick[client] = 0;
			gI_SyncedTick[client] = 0;
			gF_RawGain[client] = 0.0;
			gF_Trajectory[client] = 0.0;
			gF_TraveledDistance[client] = NULL_VECTOR;
			gB_Duck[client] = false;
			gB_IllegalSSJ[client] = false;
			gB_InAir[client] = false;
		}

		if((buttons & IN_JUMP) > 0 && gI_TicksOnGround[client] == 1)
		{
			IsPlayerOnSlope(client);
			SSJ_GetStats(client, vel, angles);
			CheckValidSSJ(client);
			gI_TicksOnGround[client] = 0;
		}
	}
	else
	{
		MoveType movetype = GetEntityMoveType(client);
		if(movetype == MOVETYPE_WALK && GetEntProp(client, Prop_Data, "m_nWaterLevel") < 2)
		{
			SSJ_GetStats(client, vel, angles);
			gF_AirTime[client] += GetGameFrameTime();
		}
		
		if((buttons & IN_DUCK) > 0 && !gB_Duck[client])
		{
			gB_Duck[client] = true;
			DebugMessage(client, "Ducked");
		}
		
		CheckValidSSJ(client);
		gB_InAir[client] = true;
		gI_TicksOnGround[client] = 0;
	}

	int iPButtons = buttons;

	if((gI_LastButtons[client] & IN_FORWARD) == 0 && (buttons & IN_FORWARD) > 0)
	{
		gI_Strafes[client]++;
	}

	if((gI_LastButtons[client] & IN_BACK) == 0 && (buttons & IN_BACK) > 0)
	{
		gI_Strafes[client]++;
	}

	if((gI_LastButtons[client] & IN_MOVELEFT) == 0 && (buttons & IN_MOVELEFT) > 0)
	{
		gI_Strafes[client]++;
	}

	if((gI_LastButtons[client] & IN_MOVERIGHT) == 0 && (buttons & IN_MOVERIGHT) > 0)
	{
		gI_Strafes[client]++;
	}
	
	if(gB_TouchesWall[client])
	{
		gI_TouchTicks[client]++;
		gB_TouchesWall[client] = false;
	}
	else
	{
		gI_TouchTicks[client] = 0;
	}
	
	GetClientAbsOrigin(client, gF_LastOrigin[client]);
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", gF_LastVel[client]);
	gI_LastButtons[client] = iPButtons;

	return Plugin_Continue;
}

void SaveStats(int client)
{
	if(gB_IllegalSSJ[client])
	{
		return;
	}
	
	float velocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);
	velocity[2] = 0.0;

	float origin[3];
	GetClientAbsOrigin(client, origin);
	
	float coeffsum = gF_RawGain[client];
	coeffsum /= gI_StrafeTick[client];
	coeffsum *= 100.0;
	
	float distance = GetVectorLength(gF_TraveledDistance[client]);

	if(distance > gF_Trajectory[client])
	{
		distance = gF_Trajectory[client];
	}

	float efficiency = 0.0;

	if(distance > 0.0)
	{
		efficiency = coeffsum * distance / gF_Trajectory[client];
	}
	
	coeffsum = RoundToFloor(coeffsum * 100.0 + 0.5) / 100.0;
	efficiency = RoundToFloor(efficiency * 100.0 + 0.5) / 100.0;
	
	int i = gI_Jump[client]-1;
	gA_PlayerStats[client][i].iSpeed = RoundToFloor(GetVectorLength(velocity));
	gA_PlayerStats[client][i].fHeight = origin[2] - GetGroundUnits(client);
	if(i == 0)
	{
		gA_PlayerStats[client][i].fGain = 0.0;
		gA_PlayerStats[client][i].fEfficiency = 0.0;
		gA_PlayerStats[client][i].fSync = 0.0;
		gA_PlayerStats[client][i].iStrafes = 0;
		gA_PlayerStats[client][i].fAirTime = 0.0;
	}
	else
	{
		gA_PlayerStats[client][i].fGain = coeffsum;
		gA_PlayerStats[client][i].fEfficiency = efficiency;
		gA_PlayerStats[client][i].fSync = (100.0 * gI_SyncedTick[client] / gI_StrafeTick[client]);
		gA_PlayerStats[client][i].iStrafes = gI_Strafes[client];
		gA_PlayerStats[client][i].fAirTime = gF_AirTime[client];
	}
	
	if(gI_Jump[client] == 6)
	{
		CheckLastJump(client);
		
		if(gB_IllegalSSJ[client])
		{
			return;
		}

		SSJTopUpdate(client, gB_Duck[client]);
	}
}

void TopMoveDown(int duck, int iOldPos, int iPos)
{
	// move entries down for insertion
	for(int i = iOldPos-1; i >= iPos; i--)
	{
		strcopy(gA_TopStats[duck][i + 1].sName, 64, gA_TopStats[duck][i].sName);
		strcopy(gA_TopStats[duck][i + 1].sAuth, 32, gA_TopStats[duck][i].sAuth);
		gA_TopStats[duck][i + 1].iTopSpeed = gA_TopStats[duck][i].iTopSpeed;
		gA_TopStats[duck][i + 1].iTimeStamp = gA_TopStats[duck][i].iTimeStamp;
		
		for(int j = 0; j < 6; j++)
		{
			gA_TopStats[duck][i + 1].iSpeed[j] = gA_TopStats[duck][i].iSpeed[j];
			gA_TopStats[duck][i + 1].fGain[j] = gA_TopStats[duck][i].fGain[j];
			gA_TopStats[duck][i + 1].fEfficiency[j] = gA_TopStats[duck][i].fEfficiency[j];
			gA_TopStats[duck][i + 1].fSync[j] = gA_TopStats[duck][i].fSync[j];
			gA_TopStats[duck][i + 1].iStrafes[j] = gA_TopStats[duck][i].iStrafes[j];
		}
	}
}

void TopMoveUp(int duck, int iPos)
{
	for(int i = iPos; i < RANKSCOUNT-2; i++)
	{
		strcopy(gA_TopStats[duck][i].sName, 64, gA_TopStats[duck][i + 1].sName);
		strcopy(gA_TopStats[duck][i].sAuth, 32, gA_TopStats[duck][i + 1].sAuth);
		gA_TopStats[duck][i].iTopSpeed = gA_TopStats[duck][i + 1].iTopSpeed;
		gA_TopStats[duck][i].iTimeStamp = gA_TopStats[duck][i + 1].iTimeStamp;
		
		for(int j = 0; j < 6; j++)
		{
			gA_TopStats[duck][i].iSpeed[j] = gA_TopStats[duck][i + 1].iSpeed[j];
			gA_TopStats[duck][i].fGain[j] = gA_TopStats[duck][i + 1].fGain[j];
			gA_TopStats[duck][i].fEfficiency[j] = gA_TopStats[duck][i + 1].fEfficiency[j];
			gA_TopStats[duck][i].fSync[j] = gA_TopStats[duck][i + 1].fSync[j];
			gA_TopStats[duck][i].iStrafes[j] = gA_TopStats[duck][i + 1].iStrafes[j];
		}
	}
	
	// Clear last entry to prevent duplicates
	strcopy(gA_TopStats[duck][RANKSCOUNT-1].sName, 64, "");
	strcopy(gA_TopStats[duck][RANKSCOUNT-1].sAuth, 32, "");
	gA_TopStats[duck][RANKSCOUNT-1].iTopSpeed = 0;
	gA_TopStats[duck][RANKSCOUNT-1].iTimeStamp = 0;
	
	for(int j = 0; j < 6; j++)
	{
		gA_TopStats[duck][RANKSCOUNT-1].iSpeed[j] = 0;
		gA_TopStats[duck][RANKSCOUNT-1].fGain[j] = 0.0;
		gA_TopStats[duck][RANKSCOUNT-1].fEfficiency[j] = 0.0;
		gA_TopStats[duck][RANKSCOUNT-1].fSync[j] = 0.0;
		gA_TopStats[duck][RANKSCOUNT-1].iStrafes[j] = 0;
	}
}

void SSJTopUpdate(int client, int duck)
{
	char sName[64], sAuth[32];
	GetClientName(client, sName, 64);
	ReplaceString(sName, 32, "#", "?");
	GetClientAuthId(client, AuthId_Steam3, sAuth, 32);
	
	int iPos = 0;
	for(; iPos < RANKSCOUNT-1 && gA_PlayerStats[client][5].iSpeed < gA_TopStats[duck][iPos].iTopSpeed; iPos++)
	{
		if(StrEqual(gA_TopStats[duck][iPos].sAuth, sAuth))
		{
			// player already has better record
			DebugMessage(client, "No PB");
			gA_TopStats[duck][iPos].sName = sName; // update name
			return;
		}
	}
	
	int iOldPos = -1;
	for(int i = 0; i < RANKSCOUNT; i++)
	{
		if(StrEqual(gA_TopStats[duck][i].sAuth, sAuth))
		{
			iOldPos = i;
			break;
		}
	}
	
	if(iPos == RANKSCOUNT-1 && gA_PlayerStats[client][5].iSpeed < gA_TopStats[duck][iPos].iTopSpeed)
	{
		DebugMessage(client, "RANK > %d", RANKSCOUNT);
		return;
	}
	
	TopMoveDown(duck, iOldPos == -1 ? RANKSCOUNT-1 : iOldPos, iPos);
	
	// overwrite entry
	strcopy(gA_TopStats[duck][iPos].sName, 64, sName);
	strcopy(gA_TopStats[duck][iPos].sAuth, 32, sAuth);
	gA_TopStats[duck][iPos].iTopSpeed = gA_PlayerStats[client][5].iSpeed;
	gA_TopStats[duck][iPos].iTimeStamp = GetTime();
	
	for(int j = 0; j < 6; j++)
	{
		gA_TopStats[duck][iPos].iSpeed[j] = gA_PlayerStats[client][j].iSpeed;
		gA_TopStats[duck][iPos].fGain[j] = gA_PlayerStats[client][j].fGain;
		gA_TopStats[duck][iPos].fEfficiency[j] = gA_PlayerStats[client][j].fEfficiency;
		gA_TopStats[duck][iPos].fSync[j] = gA_PlayerStats[client][j].fSync;
		gA_TopStats[duck][iPos].iStrafes[j] = gA_PlayerStats[client][j].iStrafes;
	}
	
	DB_SaveTop();
	TopCreateMenu(duck);
	
	if(iPos == 0)
	{
		SSJTOP_PrintToChat(0, "New TOP SSJ%s by %s%s %s(%s%d%s).", duck ? " (DUCK)" : "", gS_Variable, gA_TopStats[duck][iPos].sName, gS_Text, gS_Variable, gA_TopStats[duck][iPos].iTopSpeed, gS_Text);
	}
}

//----------------Checking cheating-------------------//
void CheckLastJump(int client)
{
	if(gB_IllegalSSJ[client])
	{
		return;
	}
	
	int strafes = 0;
	
	for(int i = 0; i < 6; i++)
	{
		// Checking Height
		int heightdiff = RoundToFloor(gA_PlayerStats[client][i].fHeight) - RoundToFloor(gA_PlayerStats[client][0].fHeight);
		if(heightdiff != 0)
		{
			DebugMessage(client, "Invalid Height Value: %s%i", gS_Variable, heightdiff);
			gB_IllegalSSJ[client] = true;
			return;
		}
		
		// Checking AirTime
		float airtime = gA_PlayerStats[client][i].fAirTime;
		if(airtime > 0.8)
		{
			DebugMessage(client, "Invalid Airtime: %s%.1f", gS_Variable, airtime);
			gB_IllegalSSJ[client] = true;
			return;
		}
		
		strafes += gA_PlayerStats[client][i].iStrafes;	
	}
	
	// Checking Strafes Count
	if(strafes < 5 || strafes > 50)
	{
		DebugMessage(client, "Invalid Strafes Count: %s%i", gS_Variable, strafes);
		gB_IllegalSSJ[client] = true;
		return;
	}
	
	// Checking Prespeed
	if(gA_PlayerStats[client][0].iSpeed > 290)
	{
		DebugMessage(client, "Invalid PreSpeed: %d", gA_PlayerStats[client][0].iSpeed);
		gB_IllegalSSJ[client] = true;
		return;
	}
}

void CheckValidSSJ(int client)
{
	if(gB_IllegalSSJ[client])
	{
		return;
	}
	
	// Checking gravity
	float fGravity = GetEntPropFloat(client, Prop_Data, "m_flGravity");
	if(fGravity != 1.0 && fGravity != 0.0)
	{
		DebugMessage(client, "Invalid Gravity");
		gB_IllegalSSJ[client] = true;
		return;
	}
	
	// Checking LaggedMovementValue
	if(GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue") != 1.0)
	{
		DebugMessage(client, "Invalid LaggedMovementValue");
		gB_IllegalSSJ[client] = true;
		return;
	}
	
	// Checking Movetype
	if(GetEntityMoveType(client) != MOVETYPE_WALK)
	{
		DebugMessage(client, "Invalid MoveType");
		gB_IllegalSSJ[client] = true;
		return;
	}
	
	// Checking IN_LEFT/IN_RIGHT
	if(GetClientButtons(client) & (IN_LEFT|IN_RIGHT))
	{
		DebugMessage(client, "+LEFT/+RIGHT");
		gB_IllegalSSJ[client] = true;
		return;
	}
	
	// Checking Validity Prestrafe
	if(gB_InAir[client] && gI_Jump[client] == 0)
	{
		DebugMessage(client, "Invalid Pre");
		gB_IllegalSSJ[client] = true;
		return;
	}
	
	float vOrigin[3], vLastOrig[3], vVel[3], vLastVel[3];
	
	GetClientAbsOrigin(client, vOrigin);
	vOrigin[2] = 0.0;
	
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vVel);
	vVel[2] = 0.0;
	
	vLastOrig[0] = gF_LastOrigin[client][0];
	vLastOrig[1] = gF_LastOrigin[client][1];
	vLastOrig[2] = 0.0;
	
	vLastVel[0] = gF_LastVel[client][0];
	vLastVel[1] = gF_LastVel[client][1];
	vLastVel[2] = 0.0;
	
	// Sharp Changes in Speed
	if(RoundToFloor(GetVectorLength(vVel) - GetVectorLength(vLastVel)) > 30)
	{
		DebugMessage(client, "Invalid Speed Changes: %s%d", gS_Variable, RoundToFloor(GetVectorLength(vVel) - GetVectorLength(vLastVel)));
		gB_IllegalSSJ[client] = true;
		return;
	}

	// Teleporting checking | Credits: LJSTATS
	if(GetVectorDistance(vLastOrig, vOrigin) > GetVectorLength(vVel) / (1.0 / gF_Tickrate) + 0.001)
	{
		DebugMessage(client, "Teleported");
		gB_IllegalSSJ[client] = true;
		return;
	}
}

public Action OnTouch(int client, int entity)
{
	if((GetEntProp(entity, Prop_Data, "m_usSolidFlags") & 12) == 0)
	{
		gB_TouchesWall[client] = true;
	}

	// Checking for touching Walls/Surf/Entities
	if(!(GetEntityFlags(client) & FL_ONGROUND) && !gB_IllegalSSJ[client])
	{
		char strClassname[64];
		GetEdictClassname(entity, strClassname, sizeof(strClassname));
		
		if(strcmp(strClassname, "trigger_multiple"))
		{
			DebugMessage(client, "%s", entity == 0 ? "Wall Touched" : "Entity Touched");
			gB_IllegalSSJ[client] = true;
		}

	}
}

// Checking Slopes | Credits: rio_(rngfix)
void IsPlayerOnSlope(int client)
{
	if (!IsPlayerAlive(client)) return;
	if (GetEntityMoveType(client) != MOVETYPE_WALK) return;
	if (GetEntProp(client, Prop_Data, "m_nWaterLevel") > 1) return;
	if (gB_IllegalSSJ[client]) return;

	float origin[3], landingMins[3], landingMaxs[3], nrm[3];

	GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", origin);
	GetEntPropVector(client, Prop_Data, "m_vecMins", landingMins);
	GetEntPropVector(client, Prop_Data, "m_vecMaxs", landingMaxs);

	float originBelow[3];
	originBelow[0] = origin[0];
	originBelow[1] = origin[1];
	originBelow[2] = origin[2] - 2.0;

	TR_TraceHullFilter(origin, originBelow, landingMins, landingMaxs, MASK_PLAYERSOLID, PlayerFilter);

	if (TR_DidHit())
	{
		TR_GetPlaneNormal(null, nrm);
		if(nrm[2] < 0.99)
		{
			DebugMessage(client, "Slope: %s%.3f", gS_Variable, nrm[2]);
			gB_IllegalSSJ[client] = true;
		}
	}
}

//Thanks MARU (https://steamcommunity.com/profiles/76561197970936804)
float GetGroundUnits(int client)
{
	if (!IsPlayerAlive(client)) return 0.0;
	if (GetEntityMoveType(client) != MOVETYPE_WALK) return 0.0;
	if (GetEntProp(client, Prop_Data, "m_nWaterLevel") > 1) return 0.0;

	float origin[3], originBelow[3], landingMins[3], landingMaxs[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", origin);
	GetEntPropVector(client, Prop_Data, "m_vecMins", landingMins);
	GetEntPropVector(client, Prop_Data, "m_vecMaxs", landingMaxs);

	originBelow[0] = origin[0];
	originBelow[1] = origin[1];
	originBelow[2] = origin[2] - 2.0;

	TR_TraceHullFilter(origin, originBelow, landingMins, landingMaxs, MASK_PLAYERSOLID, PlayerFilter, client);
	if(TR_DidHit())
	{
		TR_GetEndPosition(originBelow, null);
		float defaultheight = originBelow[2] - RoundToFloor(originBelow[2]);
		if(defaultheight > 0.03125)
		{
			defaultheight = 0.03125;
		}
		float groundunits = origin[2] - originBelow[2] + defaultheight;
		return groundunits;
	}
	else
	{
		return 0.0;
	}
}

//------------------------------------------------//

void SQL_DBConnect()
{
	gH_SQL = GetSSJTOPDatabase();
	gB_MySQL = IsMySQLDatabase2(gH_SQL);

	// support unicode names
	if(!gH_SQL.SetCharset("utf8mb4"))
	{
		gH_SQL.SetCharset("utf8");
	}
	
	if(gB_MySQL)
	{
		gH_SQL.Query(SQL_CreateTable_Callback, gS_MySQL_CreateTopTable);
	}
	else
	{
		gH_SQL.Query(SQL_CreateTable_Callback, gS_SQLITE_CreateTopTable);
	}
	
	gH_SQL.Query(SQL_CreateTable_Callback, gS_CreateJumpsTable);
}

public void SQL_CreateTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("[SSJ TOP] Error! datatable creation failed. Reason: %s", error);

		return;
	}
}

void DB_LoadTop()
{
	gH_SQL.Query(DB_LoadTop_Callback, gS_LoadTop);
	gH_SQL.Query(DB_LoadTopJumps_Callback, gS_LoadTopJumps);
}

public void DB_LoadTop_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("DB_LoadSSJTop failed: %s", error);
		return;
	}
	
	while(results.FetchRow())
	{
		char sName[64], sAuth[32];
		
		int duck = results.FetchInt(0);
		int rank = results.FetchInt(1);
		
		results.FetchString(2, sAuth, sizeof(sAuth));
		results.FetchString(3, sName, sizeof(sName));
		
		strcopy(gA_TopStats[duck][rank].sAuth, 32, sAuth);
		strcopy(gA_TopStats[duck][rank].sName, 64, sName);
		
		gA_TopStats[duck][rank].iTopSpeed = results.FetchInt(4);
		gA_TopStats[duck][rank].iTimeStamp = results.FetchInt(5);
	}
	
	TopCreateMainMenu();
	TopCreateMenu(0);
	TopCreateMenu(1);
}

public void DB_LoadTopJumps_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("DB_LoadSSJTopJumps failed: %s", results);
		return;
	}
	
	while(results.FetchRow())
	{
		int duck = results.FetchInt(0);
		int rank = results.FetchInt(1);
		int jump = results.FetchInt(2);
		
		gA_TopStats[duck][rank].iSpeed[jump] = results.FetchInt(3);
		gA_TopStats[duck][rank].fGain[jump] = results.FetchFloat(4);
		gA_TopStats[duck][rank].fEfficiency[jump] = results.FetchFloat(5);
		gA_TopStats[duck][rank].fSync[jump] = results.FetchFloat(6);
		gA_TopStats[duck][rank].iStrafes[jump] = results.FetchInt(7);
	}
}

void DB_SaveTop()
{
	gH_SQL.Query(DB_EmptyCallback, gS_DeleteTop);
	gH_SQL.Query(DB_EmptyCallback, gS_DeleteTopJumps);
	
	Transaction hTxn = new Transaction();
	
	char sQuery[256];
	
	for(int i = 0; i < 2; i++)
	{
		for (int j = 0; j < RANKSCOUNT; j++)
		{
			if (gA_TopStats[i][j].sAuth[0] == 0)
				continue;
			
			char EscapedName[64];
			if (!gH_SQL.Escape(gA_TopStats[i][j].sName, EscapedName, sizeof(EscapedName)))
			{
				LogError("Failed to escape %s's name when writing ssjs to database! Writing name without quotes instead", gA_TopStats[i][j].sName);
				strcopy(EscapedName, sizeof(EscapedName), gA_TopStats[i][j].sName);
				int index;
				while ((index = StrContains(EscapedName, "'")) != -1)
				{
					strcopy(EscapedName[index], sizeof(EscapedName) - index, EscapedName[index + 1]);
				}
			}
			FormatEx(sQuery, sizeof(sQuery), "INSERT INTO ssjtop (duck, rank, auth, name, velocity, date) VALUES (%d, %d, '%s', '%s', %d, %d)",
			i,
			j,
			gA_TopStats[i][j].sAuth,
			EscapedName,
			gA_TopStats[i][j].iTopSpeed,
			gA_TopStats[i][j].iTimeStamp);
			
			hTxn.AddQuery(sQuery);
			
			for (int k = 0; k < 6; k++)
			{
				FormatEx(sQuery, sizeof(sQuery), "INSERT INTO ssjtopjumps (duck, rank, jump, velocity, gain, efficiency, sync, strafes) VALUES (%d, %d, %d, %d, %f, %f, %f, %d)",
				i,
				j,
				k,
				gA_TopStats[i][j].iSpeed[k],
				gA_TopStats[i][j].fGain[k],
				gA_TopStats[i][j].fEfficiency[k],
				gA_TopStats[i][j].fSync[k],
				gA_TopStats[i][j].iStrafes[k]);
			
				hTxn.AddQuery(sQuery);
			}
		}
	}
	
	gH_SQL.Execute(hTxn, DB_TxnSuccess, DB_TxnFailure);
}

public void DB_EmptyCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError(error);
	}
}

public void DB_TxnSuccess(Database db, any data, int numQueries, Handle[] results, any[] queryData)
{

}

public void DB_TxnFailure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("DB_SaveSSJTop: Transaction failed: %s", error);
}

void TopCreateMainMenu()
{
	if(gM_TopMainMenu != null)
	{
		delete gM_TopMainMenu;
	}
	
	gM_TopMainMenu = new Menu(TopMainMenuHandler);
	
	gM_TopMainMenu.SetTitle("SSJ Top Main Menu\n ");
	
	gM_TopMainMenu.AddItem("noduck", "No Duck");
	gM_TopMainMenu.AddItem("duck", "Duck");
}

public int TopMainMenuHandler(Menu menu, MenuAction action, int client, int item)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			gM_TopMenus[item].Display(client, MENU_TIME_FOREVER);
		}
		
		case MenuAction_Cancel:
		{
			gB_DeleteMode[client] = false;
		}
	}
}

void TopCreateMenu(int duck)
{
	if(gM_TopMenus[duck] != null)
	{
		delete gM_TopMenus[duck];
	}
	
	gM_TopMenus[duck] = new Menu(TopRecordMenuHandler);
	
	char buf[128], info[8];
	
	Format(buf, sizeof(buf), "SSJ Top (%s)\n ", duck ? "Duck" : "No Duck");
	
	gM_TopMenus[duck].SetTitle(buf);
	
	for(int i; i < RANKSCOUNT; i++)
	{
		if(gA_TopStats[duck][i].sName[0] == 0)
		{
			break;
		}
		
		FormatEx(buf, sizeof(buf), "%s - %d", gA_TopStats[duck][i].sName, gA_TopStats[duck][i].iTopSpeed);
		
		FormatEx(info, sizeof(info), "%d;%d", duck, i);
		
		gM_TopMenus[duck].AddItem(info, buf);
	}
	//gM_TopMenus[duck].ExitBackButton = true;
}

public int TopRecordMenuHandler(Menu menu, MenuAction action, int client, int item)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char info[8];
			
			if(!GetMenuItem(menu, item, info, sizeof(info)))
			{
				return 0;
			}
			
			char split[2][16], sTime[128], buf[128];
			ExplodeString(info, ";", split, sizeof(split), sizeof(split[]));
			
			int duck = gI_LastChoice[client] = StringToInt(split[0]);
			int rank = StringToInt(split[1]);
			
			if(gB_DeleteMode[client])
			{
				OpenDeleteMenu(client, duck, rank);
				return 0;
			}
			
			Panel hPanel = new Panel();
			
			FormatTime(sTime, sizeof(sTime), NULL_STRING, gA_TopStats[duck][rank].iTimeStamp); // "%B %d %Y %T"
			
			FormatEx(buf, sizeof(buf), "%s %s", gA_TopStats[duck][rank].sName, gA_TopStats[duck][rank].sAuth);
			hPanel.SetTitle(buf);
			
			FormatEx(buf, sizeof(buf), "SSJ: %d %s\n ", gA_TopStats[duck][rank].iTopSpeed, duck ? "(Duck)" : "(No Duck)");
			hPanel.DrawText(buf);
			
			hPanel.DrawText("Jump | Speed | Gain | Efficiency | Sync | Strafes\n ");
			
			FormatEx(buf, sizeof(buf), "%d      %d", 1, gA_TopStats[duck][rank].iSpeed[0]);
			hPanel.DrawText(buf);
			
			for(int i = 1; i < 6; i++)
			{
				FormatEx(buf, sizeof(buf), "%d      %d      %.2f%%      %.2f%%      %.2f%%      %d%s", i + 1, gA_TopStats[duck][rank].iSpeed[i], gA_TopStats[duck][rank].fGain[i], gA_TopStats[duck][rank].fEfficiency[i], gA_TopStats[duck][rank].fSync[i], gA_TopStats[duck][rank].iStrafes[i], i == 5 ? "\n " : "");
				hPanel.DrawText(buf);
			}
			
			hPanel.DrawText(sTime);
			
			hPanel.Send(client, RecordPanelHandler, MENU_TIME_FOREVER);
			
			delete hPanel;
		}
		
		case MenuAction_Cancel:
		{
			if(item == MenuCancel_Exit)
			{
				gM_TopMainMenu.Display(client, MENU_TIME_FOREVER);
			}
		}
	}
	return 0;
}

public int RecordPanelHandler(Menu menu, MenuAction action, int client, int item)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			gM_TopMenus[gI_LastChoice[client]].Display(client, MENU_TIME_FOREVER);
		}
	}
}

void OpenDeleteMenu(int client, int duck, int rank)
{
	char sMenuItem[64], sTitle[64];

	Menu menu = new Menu(DeleteConfirm_Handler);
	FormatEx(sTitle, 64, "Delete %s's %d (%s)\nAre you sure?\n ", gA_TopStats[duck][rank].sName, gA_TopStats[duck][rank].iTopSpeed, duck ? "Duck" : "No Duck");
	menu.SetTitle(sTitle);

	for(int i = 1; i <= GetRandomInt(1, 4); i++)
	{
		FormatEx(sMenuItem, 64, "NO!");
		menu.AddItem("-1;-1", sMenuItem);
	}

	FormatEx(sMenuItem, 64, "YES!!! DELETE!!!");

	char sInfo[16];
	FormatEx(sInfo, 16, "%d;%d", duck, rank);
	menu.AddItem(sInfo, sMenuItem);

	for(int i = 1; i <= GetRandomInt(1, 3); i++)
	{
		FormatEx(sMenuItem, 64, "NO!");
		menu.AddItem("-1;-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.Display(client, 20);
}

public int DeleteConfirm_Handler(Menu menu, MenuAction action, int client, int item)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(item, sInfo, 16);

		char split[2][4];
		ExplodeString(sInfo, ";", split, sizeof(split), sizeof(split[]));
		
		int duck = StringToInt(split[0]);
		int rank = StringToInt(split[1]);

		if(duck == -1)
		{
			SSJTOP_PrintToChat(client, "Aborted deletion.");
			return 0;
		}
		
		SSJTOP_PrintToChat(client, "Removing %s's %s%d %s%s", gA_TopStats[duck][rank].sName, gS_Variable, gA_TopStats[duck][rank].iTopSpeed, gS_Text, duck ? "(duck)" : "(noduck)");
		TopMoveUp(duck, rank);
		DB_SaveTop();
		TopCreateMenu(duck);
		
		gB_DeleteMode[client] = false;
	}

	else if(action == MenuAction_End)
	{
		gB_DeleteMode[client] = false;
		delete menu;
	}

	return 0;
}

Database GetSSJTOPDatabase()
{
	Database db = null;
	char sError[255];

	if(SQL_CheckConfig("ssjtop"))
	{
		if((db = SQL_Connect("ssjtop", true, sError, 255)) == null)
		{
			SetFailState("[SSJ TOP] startup failed. Reason: %s", sError);
		}
	}

	else
	{
		db = SQLite_UseDatabase("ssjtop", sError, 255);
	}

	return db;
}

bool IsMySQLDatabase2(Database db)
{
	char sDriver[8];
	db.Driver.GetIdentifier(sDriver, 8);

	return StrEqual(sDriver, "mysql", false);
}

//Filter
public bool PlayerFilter(int entity, int mask)
{
	return !(1 <= entity <= MaxClients);
}

void DebugMessage(int client, const char[] msg, any ...)
{
	if(gB_DebugMessages)
	{
		char buffer[300];
		VFormat(buffer, sizeof(buffer), msg, 3);
		SSJTOP_PrintToChat(client, "%s%s.", buffer, gS_Text);
	}
}

void SSJTOP_PrintToChat(int client = 0, const char[] msg, any ...)
{
	if (client != 0)
	{
		if (!IsClientInGame(client))
		{
			return;
		}
	}
	
	bool bAll = client == 0;
	
	char buffer[300];
	VFormat(buffer, sizeof(buffer), msg, 3);
	
	Format(buffer, sizeof(buffer), "%s%s[SSJ TOP]%s %s", gEV_Type == Engine_CSS ? "" : " ", gS_Variable, gS_Text, buffer);
	
	Handle hMessage = bAll ? StartMessageAll("SayText2") : StartMessageOne("SayText2", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS); 
	if (hMessage != INVALID_HANDLE) 
	{
		if(GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf) 
		{
			PbSetInt(hMessage, "ent_idx", client);
			PbSetBool(hMessage, "chat", bAll);
			PbSetString(hMessage, "msg_name", buffer);
			PbAddString(hMessage, "params", "");
			PbAddString(hMessage, "params", "");
			PbAddString(hMessage, "params", "");
			PbAddString(hMessage, "params", "");
		}
		else
		{
			BfWriteByte(hMessage, client);
			BfWriteByte(hMessage, bAll);
			BfWriteString(hMessage, buffer);
		}
		
		EndMessage();
	}
}