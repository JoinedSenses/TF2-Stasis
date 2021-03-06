#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>

#define PIPE_TICKS_UNTIL_EXPLODE 145
#define SLOTCOUNT 3
#define PLUGIN_VERSION "1.0.0"
#define PLUGIN_DESCRIPTION "Stasis: A state which does not change"

enum {
	PRIMARYATTACK,
	SECONDARYATTACK
}

float g_vOrigin[MAXPLAYERS+1][3];
float g_vVelocity[MAXPLAYERS+1][3];

float g_fNextAttack[MAXPLAYERS+1][SLOTCOUNT][2];
float g_fStasisTick[MAXPLAYERS+1];

bool g_bStasis[MAXPLAYERS+1];

int g_iBeamSprite;
int g_iHaloSprite;

ArrayList g_aProjectiles[MAXPLAYERS+1];
ArrayList g_aVPhysicsEntities;

StringMap g_smProjectileOrigin[MAXPLAYERS+1];
StringMap g_smProjectileAngles[MAXPLAYERS+1];
StringMap g_smProjectileVelocity[MAXPLAYERS+1];
StringMap g_smProjectileMoveType[MAXPLAYERS+1];
StringMap g_smProjectileExplodeTime[MAXPLAYERS+1];

int g_iStasisButtons[MAXPLAYERS+1];

int g_iOldTick[MAXPLAYERS+1];

public Plugin myinfo = {
	name = "Stasis",
	author = "JoinedSenses",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "http://github.com/JoinedSenses"
};

// ================= SM API

public void OnPluginStart() {
	CreateConVar("sm_stasis_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD).SetString(PLUGIN_VERSION);

	RegAdminCmd("sm_stasis", cmdStasis, ADMFLAG_RESERVATION);

	HookEvent("player_team", eventPlayerStatusChange);
	HookEvent("player_changeclass", eventPlayerStatusChange);
	HookEvent("player_death", eventPlayerStatusChange);
	HookEvent("player_disconnect", eventPlayerStatusChange);

	g_aVPhysicsEntities = new ArrayList(6);

	for (int i = 1; i <= MaxClients; i++) {
		g_aProjectiles[i] = new ArrayList(6);
		g_smProjectileOrigin[i] = new StringMap();
		g_smProjectileAngles[i] = new StringMap();
		g_smProjectileVelocity[i] = new StringMap();
		g_smProjectileMoveType[i] = new StringMap();
		g_smProjectileExplodeTime[i] = new StringMap();
	}
}

public void OnMapStart() {
	g_iBeamSprite = PrecacheModel("sprites/laser.vmt", true);
	g_iHaloSprite = PrecacheModel("sprites/halo01.vmt", true);

	g_aVPhysicsEntities.Clear();

	for (int i = 1; i <= MaxClients; i++) {
		ResetValues(i);
	}
}

public void OnPluginEnd() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsValidClient(i) && IsClientInStasis(i)) {
			ToggleStasis(i);
			PrintToChat(i, "Stasis ending. Plugin reloading");
		}
	}
}

public void OnGameFrame() {
	int entcount;
	if (!(entcount = VPhysicsEntityCount())) {
		return;
	}
	// ArrayList of pipes/stickies
	for (int i = 0; i < entcount; i++) {
		int entity = GetVPhysicsEntityByIndex(i);

		if (!IsValidEntity(entity)) {
			continue;
		}

		int owner = HasEntProp(entity, Prop_Send, "m_hThrower") ? GetEntPropEnt(entity, Prop_Send, "m_hThrower") : -1;
		if (!IsValidClient(owner) || !IsClientInStasis(owner)) {
			continue;
		}

		char sEntity[5];
		Format(sEntity, sizeof(sEntity), "%i", entity);

		// Checking if this is grenade-like entity
		if (GetExplodeTime(owner, sEntity)) {
			int tick = GetEntProp(entity, Prop_Data, "m_nNextThinkTick");
			SetEntProp(entity, Prop_Data, "m_nNextThinkTick", tick+1);
		}

		// Some dumb method of preventing vphysics entites from getting stuck in the air by keeping them "moving".
		float fakevelocity[3] = {0.001, 0.001, 0.001};
		TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, fakevelocity);
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	if (!IsClientInStasis(client)) {
		return Plugin_Continue;
	}

	TFClassType class = TF2_GetPlayerClass(client);
	Action action = Plugin_Continue;
	switch (class) {
		case TFClass_Soldier, TFClass_Medic: {
			return Plugin_Continue;
		}
		case TFClass_DemoMan: {
			int playerweapon;
			if ((playerweapon = Client_GetActiveWeapon(client)) == INVALID_ENT_REFERENCE) {
				return Plugin_Continue;
			}

			char classname[64];
			GetEntityClassname(playerweapon, classname, sizeof(classname));

			if (StrEqual(classname, "tf_weapon_pipebomblauncher")) {
				float starttime = GetEntPropFloat(playerweapon, Prop_Send, "m_flChargeBeginTime");
				if (starttime) {
					// Hold sticky charge if it has began
					SetEntPropFloat(playerweapon, Prop_Send, "m_flChargeBeginTime", starttime+GetTickInterval());
				}
			}
			else if (StrEqual(classname, "tf_weapon_cannon")) {
				float dettime = GetEntPropFloat(playerweapon, Prop_Send, "m_flDetonateTime");
				if (dettime) {
					SetEntPropFloat(playerweapon, Prop_Send, "m_flDetonateTime", dettime+GetTickInterval());
					//SetEntProp(playerweapon, Prop_Send, "m_nSequence", 0);
					//PrintToChatAll("%0.2f", GetEntPropFloat(playerweapon, Prop_Send, "m_flPlaybackRate"));
				}
			}
		}
		case TFClass_Heavy: {
			if (g_iStasisButtons[client] & IN_ATTACK2) {
				buttons |= IN_ATTACK2;
				action = Plugin_Changed;
			}
		}
		case TFClass_Sniper: {
			int playerweapon;
			if ((playerweapon = Client_GetActiveWeapon(client)) == INVALID_ENT_REFERENCE) {
				return Plugin_Continue;
			}

			char classname[64];
			GetEntityClassname(playerweapon, classname, sizeof(classname));

			if (!StrEqual(classname, "tf_weapon_compound_bow")) {
				return Plugin_Continue;
			}

			float starttime = GetEntPropFloat(playerweapon, Prop_Send, "m_flChargeBeginTime");
			if (starttime) {
				SetEntPropFloat(playerweapon, Prop_Send, "m_flChargeBeginTime", starttime+GetTickInterval());
			}
		}
	}

	if (g_iStasisButtons[client] & IN_ATTACK) {
		buttons |= IN_ATTACK;
		action = Plugin_Changed;
	}

	return action;
}

public void OnEntityCreated(int entity, const char[] classname) {
	// Requst game frame to retrieve information that isn't set yet.
	if (StrContains(classname, "projectile_pipe") != -1 || StrContains(classname, "projectile_jar") != -1) {
		RequestFrame(frameSpawnPipe, entity);
		AddToVPhysicsList(entity);
	}

	else if (StrContains(classname, "tf_projectile") != -1 || StrEqual(classname, "prop_physics")) {
		RequestFrame(frameSpawnRocket, entity);
	}
}

public void OnEntityDestroyed(int entity) {
	if (!IsValidEntity(entity)) {
		return;
	}
	// Clear arrays/stringmaps when entity is destroyed
	int owner = GetEntityOwner(entity);
	if (0 < owner <= MaxClients && CheckCommandAccess(owner, "sm_stasis", ADMFLAG_RESERVATION)) {
		ClearEntity(owner, entity);
	}
}

// ================= Hooks

public Action eventPlayerStatusChange(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client) {
		ResetValues(client);
	}
}

// ================= Commands

public Action cmdStasis(int client, int args) {
	if (!client || IsClientObserver(client)) {
		return Plugin_Handled;
	}
	// Restriction until stable for all classes
	TFClassType class = TF2_GetPlayerClass(client);
	if (class != TFClass_Soldier && class != TFClass_DemoMan) {
		PrintToChat(client, "Unsupported class");
		return Plugin_Handled;
	}

	ToggleStasis(client);
	return Plugin_Handled;
}

// ================= Internal Functions

// -- Client

void ResetValues(int client) {
	g_aProjectiles[client].Clear();
	g_smProjectileOrigin[client].Clear();
	g_smProjectileAngles[client].Clear();
	g_smProjectileVelocity[client].Clear();
	g_smProjectileMoveType[client].Clear();
	g_smProjectileExplodeTime[client].Clear();

	g_bStasis[client] = false;
	g_fStasisTick[client] = 0.0;
	g_iOldTick[client] = 0;

	for (int j = 0; j < 3; j++) {
		g_fNextAttack[client][j][PRIMARYATTACK] = 0.0;
		g_fNextAttack[client][j][SECONDARYATTACK] = 0.0;
	}
}

bool IsValidClient(int client) {
	return ((0 < client <= MaxClients) && IsClientInGame(client));
}

bool IsClientInStasis(int client) {
	return g_bStasis[client];
}

void ToggleStasis(int client) {
	if (!IsClientInStasis(client)) {
		EnableStasis(client);
	}
	else {
		DisableStasis(client);
	}	
}

void EnableStasis(int client) {
	g_bStasis[client] = true;
	FreezePlayer(client);
	PauseClientAttack(client);
	FreezeProjectiles(client);
}

void DisableStasis(int client) {
	g_bStasis[client] = false;
	UnFreezePlayer(client);
	ResumeClientAttack(client);
	UnfreezeProjectiles(client);
}

void FreezePlayer(int client) {
	// Store velocity/origin and create laser
	GetClientAbsVelocity(client, g_vVelocity[client]);

	float temp[3];
	GetVectorAngles(g_vVelocity[client], temp);

	float vForward[3];
	GetAngleVectors(temp, vForward, NULL_VECTOR, NULL_VECTOR);
	ScaleVector(vForward, GetVectorLength(vForward)*100.0);

	GetClientAbsOrigin(client, g_vOrigin[client]);
	AddVectors(g_vOrigin[client], vForward, temp);

	LaserBeam(client, g_vOrigin[client], temp);

	// Get eye angles and create laser
	float vEyeAngles[3];
	GetClientEyeAngles(client, vEyeAngles);

	GetAngleVectors(vEyeAngles, vForward, NULL_VECTOR, NULL_VECTOR);
	ScaleVector(vForward, 80.0);

	float vEyepos[3];
	GetClientEyePosition(client, vEyepos);

	float vEnd[3];
	AddVectors(vEyepos, vForward, vEnd);

	temp = vEyepos;
	temp[2] -= 30.0;

	LaserBeam(client, temp, vEnd, 255, 20, 20);
	LaserBeam(client, vEyepos, vEnd, 255, 20, 20);

	// Freeze client
	SetEntityMoveType(client, MOVETYPE_NONE);

	// Calculations for when client can attack again
	g_fStasisTick[client] = GetGameTime();
	g_iStasisButtons[client] = GetClientButtons(client);
}

void UnFreezePlayer(int client) {
	// Unfreeze client
	SetEntityMoveType(client, MOVETYPE_WALK);
	TeleportEntity(client, g_vOrigin[client], NULL_VECTOR, g_vVelocity[client]);
}

// -- Attack

void PauseClientAttack(int client) {
	for (int slot = 0; slot < SLOTCOUNT; slot++) {
		PauseAttackForWeapon(client, GetPlayerWeaponSlot(client, slot), slot);
	}
}

void ResumeClientAttack(int client) {
	for (int slot = 0; slot < SLOTCOUNT; slot++) {
		ResumeAttackForWeapon(client, GetPlayerWeaponSlot(client, slot), slot);
	}
}

void PauseAttackForWeapon(int client, int weapon, int slot) {
	if (!IsValidEntity(weapon)) {
		return;
	}
	if (HasEntProp(weapon, Prop_Send, "m_flNextPrimaryAttack")) {
		g_fNextAttack[client][slot][PRIMARYATTACK] = GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack");
		SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", 999999999.0);		
	}
	if (HasEntProp(weapon, Prop_Send, "m_flNextSecondaryAttack")) {
		g_fNextAttack[client][slot][SECONDARYATTACK] = GetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack");
		SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", 999999999.0);
	}
}

void ResumeAttackForWeapon(int client, int weapon, int slot) {
	if (!IsValidEntity(weapon)) {
		return;
	}
	if (HasEntProp(weapon, Prop_Send, "m_flNextPrimaryAttack")) {
		SetEntPropFloat(
			  weapon
			, Prop_Send
			, "m_flNextPrimaryAttack"
			, g_fNextAttack[client][slot][PRIMARYATTACK]+(GetGameTime()-g_fStasisTick[client])
		);
	}
	if (HasEntProp(weapon, Prop_Send, "m_flNextSecondaryAttack")) {
		SetEntPropFloat(
			  weapon
			, Prop_Send
			, "m_flNextSecondaryAttack"
			, g_fNextAttack[client][slot][SECONDARYATTACK]+(GetGameTime()-g_fStasisTick[client])
		);	
	}
}

// -- Projectiles

void FreezeProjectiles(int client) {
	int count;
	if (!(count = ClientProjectileCount(client))) {
		return;
	}
	for (int i = 0; i < count; i++) {
		int entity = GetClientProjectileByIndex(client, i);

		FreezeProjectile(client, entity);
	}

	g_iOldTick[client] = GetGameTickCount();
}

void UnfreezeProjectiles(int client) {
	int count;
	if (!(count = ClientProjectileCount(client))) {
		return;
	}
	for (int i = 0; i < count; i++) {
		int entity = GetClientProjectileByIndex(client, i);

		if (!IsValidEntity(entity)) {
			ClearEntity(client, entity);
			return;
		}
		UnfreezeProjectile(client, entity);
	}
}

void FreezeProjectile(int client, int entity) {
	if (!IsValidEntity(entity)) {
		ClearEntity(client, entity);
		return;
	}

	char sEntity[5];
	Format(sEntity, sizeof(sEntity), "%i", entity);

	float origin[3];
	float angles[3];
	float velocity[3];

	Entity_GetAbsOrigin(entity, origin);
	g_smProjectileOrigin[client].SetArray(sEntity, origin, sizeof(origin));

	Entity_GetAbsAngles(entity, angles);
	g_smProjectileAngles[client].SetArray(sEntity, angles, sizeof(angles));

	Entity_GetAbsVelocity(entity, velocity);
	g_smProjectileVelocity[client].SetArray(sEntity, velocity, sizeof(velocity));

	g_smProjectileMoveType[client].SetValue(sEntity, GetEntityMoveType(entity));
	// Projectile velocity laser
	float temp[3];
	GetVectorAngles(velocity, temp);

	float vForward[3];
	float vUp[3];
	float vRight[3];
	GetAngleVectors(temp, vForward, vUp, vRight);

	ScaleVector(vForward, GetVectorLength(vForward)*100.0);
	SubtractVectors(origin, vForward, temp);
	LaserBeam(client, origin, temp, 50, 50);

	ZeroVector(temp);
	ScaleVector(vUp, GetVectorLength(vUp)*15.0);
	AddVectors(origin, vUp, temp);
	float temp2[3];
	SubtractVectors(origin, vUp, temp2);
	LaserBeam(client, temp2, temp, 100, 50);

	ZeroVector(temp);
	ZeroVector(temp2);
	ScaleVector(vRight, GetVectorLength(vRight)*15.0);
	AddVectors(origin, vRight, temp);
	SubtractVectors(origin, vRight, temp2);
	LaserBeam(client, temp, temp2, 100, 50);

	///////

	SetEntityMoveType(entity, MOVETYPE_NONE);
	TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, ZeroVector());
}

void UnfreezeProjectile(int client, int entity) {
	char sEntity[5];
	Format(sEntity, sizeof(sEntity), "%i", entity);

	float origin[3];
	float angles[3];
	float velocity[3];
	// EXIT STASIS

	g_smProjectileOrigin[client].GetArray(sEntity, origin, sizeof(origin));
	g_smProjectileAngles[client].GetArray(sEntity, angles, sizeof(angles));
	g_smProjectileVelocity[client].GetArray(sEntity, velocity, sizeof(velocity));


	//char classname[64];
	//GetEntityClassname(entity, classname, sizeof(classname));

	MoveType movetype;
	g_smProjectileMoveType[client].GetValue(sEntity, movetype);

	SetEntityMoveType(entity, movetype);
	TeleportEntity(entity, origin, angles, velocity);

	int tick;
	bool result = GetExplodeTime(client, sEntity, tick);

	if (result) {
		// Calculate nextthink for pipe lifespan
		int spentticks = g_iOldTick[client] - tick;
		int remainingticks = PIPE_TICKS_UNTIL_EXPLODE - spentticks;
		int newnextthink =  GetGameTickCount() + remainingticks;

		SetEntProp(entity, Prop_Data, "m_nNextThinkTick", newnextthink);

		//PrintToChatAll(
		//	    "Spawned: %i\n"
		//	... "Stasis tick: %i\n"
		//	... "Spent ticks: %i\n"
		//	... "Remaining ticks: %i\n"
		//	... "NextThink tick: %i"
		//	, tick, g_iOldTick[client], spentticks, remainingticks, newnextthink
		//);

		// Account for the delay from stasis
		tick += GetGameTickCount()-g_iOldTick[client];
		SetExplodeTime(client, sEntity, tick);
	}
}

// -- Projectile Entities

int ClientProjectileCount(int client) {
	return g_aProjectiles[client].Length;
}

int GetClientProjectileByIndex(int client, int index) {
	return g_aProjectiles[client].Get(index);
}

int FindClientProjectileIndex(int client, int entity) {
	return g_aProjectiles[client].FindValue(entity);
}

void RemoveClientProjectileByIndex(int client, int index) {
	g_aProjectiles[client].Erase(index);
}

void AddToClientProjectileList(int client, int entity) {
	g_aProjectiles[client].Push(entity);
}

// -- VPhysics Entities

void AddToVPhysicsList(int entity) {
	g_aVPhysicsEntities.Push(entity);
}

int FindVPhysicsEntityIndex(int entity) {
	return g_aVPhysicsEntities.FindValue(entity);
}

int GetVPhysicsEntityByIndex(int index) {
	return g_aVPhysicsEntities.Get(index);
}

void RemoveVPhysicsEntityByIndex(int index) {
	g_aVPhysicsEntities.Erase(index);
}

int VPhysicsEntityCount() {
	return g_aVPhysicsEntities.Length;
}

void SetExplodeTime(int client, const char[] entity, int tick) {
	g_smProjectileExplodeTime[client].SetValue(entity, tick);
}

bool GetExplodeTime(int client, const char[] entity, int &tick = 0) {
	return g_smProjectileExplodeTime[client].GetValue(entity, tick);
}

// -- Entity

int GetEntityOwner(int entity) {
	if (!IsValidEntity(entity)) {
		return 0;
	}

	int owner;
	if (HasEntProp(entity, Prop_Send, "m_hThrower")) {
		owner = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
	}
	if (!owner && HasEntProp(entity, Prop_Send, "m_hOwnerEntity")) {
		owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	}
	if (!owner) {
		return 0;
	}
	if (owner > MaxClients && HasEntProp(owner, Prop_Send, "m_hBuilder")) {
		owner = GetEntPropEnt(owner, Prop_Send, "m_hBuilder");
	}
	return owner;
}

void ClearEntity(int owner, int entity) {
	int index;
	if ((index = FindClientProjectileIndex(owner, entity)) != -1) {
		RemoveClientProjectileByIndex(owner, index);
	}
	if ((index = FindVPhysicsEntityIndex(entity)) != -1) {
		RemoveVPhysicsEntityByIndex(index);
	}

	char sEntity[5];
	Format(sEntity, sizeof(sEntity), "%i", entity);

	g_smProjectileOrigin[owner].Remove(sEntity);
	g_smProjectileAngles[owner].Remove(sEntity);
	g_smProjectileVelocity[owner].Remove(sEntity);
	g_smProjectileMoveType[owner].Remove(sEntity);
	g_smProjectileExplodeTime[owner].Remove(sEntity);
}

// -- Misc/Stocks

void LaserBeam(int client, float start[3], float end[3], int r = 255, int g = 255, int b = 255, int a = 255) {
	int color[4];
	color[0] = r;
	color[1] = g;
	color[2] = b;
	color[3] = a;
	TE_SetupBeamPoints(start, end, g_iBeamSprite, g_iHaloSprite, 0, 66, 10.0, 15.0, 15.0, 1, 1.0, color, 0);
	TE_SendToClient(client);
}

void Entity_GetAbsOrigin(int entity, float vec[3]) {
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", vec);
}

void Entity_GetAbsAngles(int entity, float vec[3]) {
	GetEntPropVector(entity, Prop_Data, "m_angAbsRotation", vec);
}

void Entity_GetAbsVelocity(int entity, float vec[3]) {
	GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", vec);
}

int Client_GetActiveWeapon(int client) {
	int weapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");

	if (!IsValidEntity(weapon)) {
		return INVALID_ENT_REFERENCE;
	}

	return weapon;
}

bool GetClientAbsVelocity(int client, float velocity[3]) {
	static int offset = -1;
	
	if (offset == -1 && (offset = FindDataMapInfo(client, "m_vecAbsVelocity")) == -1) {
		ZeroVector(velocity);
		return false;
	}
	
	GetEntDataVector(client, offset, velocity);
	return true;
}

float[] ZeroVector(float vec[3] = {0.0, 0.0, 0.0}) {
	vec[0] = vec[1] = vec[2] = 0.0;
	return vec;
}

// ================= Timers/Frame Requests

void frameSpawnRocket(int entity) {
	if (!IsValidEntity(entity)) {
		return;
	}
	int owner = GetEntityOwner(entity);
	if (!(0 < owner <= MaxClients) || !CheckCommandAccess(owner, "sm_stasis", ADMFLAG_RESERVATION)) {
		return;
	}
	// ArrayList of client's projectiles
	AddToClientProjectileList(owner, entity);
}

void frameSpawnPipe(int entity) {
	if (!IsValidEntity(entity)) {
		return;
	}
	int owner = GetEntityOwner(entity);
	if (!(0 < owner <= MaxClients) || !CheckCommandAccess(owner, "sm_stasis", ADMFLAG_RESERVATION)) {
		return;
	}
	// ArrayList of client's projectiles
	AddToClientProjectileList(owner, entity);

	char sEntity[5];
	Format(sEntity, sizeof(sEntity), "%i", entity);

	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));

	if (StrEqual(classname, "tf_projectile_pipe") || StrContains(classname, "projectile_jar") != -1) {
		// Get tick count of spawn - used to perform calculations for lifespan
		SetExplodeTime(owner, sEntity, GetGameTickCount());
	}
}