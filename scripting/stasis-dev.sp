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

public Plugin myinfo = {
	name = "Stasis",
	author = "JoinedSenses",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "http://github.com/JoinedSenses"
};

float g_vOrigin[MAXPLAYERS+1][3];
float g_vVelocity[MAXPLAYERS+1][3];

float g_fNextAttack[MAXPLAYERS+1][SLOTCOUNT][2];
float g_fStasisTick[MAXPLAYERS+1];

int g_iStasisButtons[MAXPLAYERS+1];
int g_iPauseTick[MAXPLAYERS+1];

bool g_bStasis[MAXPLAYERS+1];

int g_iBeamSprite;
int g_iHaloSprite;

ArrayList g_aProjectiles[MAXPLAYERS+1];
ArrayList g_aVPhysicsList;

enum {
	PRIMARYATTACK,
	SECONDARYATTACK
}

enum struct Projectile {
	int Entity;
	int Owner;
	bool IsNull;
	float Origin[3];
	float Angles[3];
	float Velocity[3];
	MoveType Movetype;
	int ExplodeTime;

	bool SetEntity(int entity) {
		if (entity > MaxClients && IsValidEntity(entity)) {
			this.Entity = entity;
			return true;
		}
		return false;
	}
	int FindOwner() {
		return (this.Owner = GetEntityOwner(this.Entity));
	}
	void Save() {
		if (this.Entity > MaxClients && IsValidEntity(this.Entity) && IsValidOwner(this.Owner)) {
			g_aProjectiles[this.Owner].PushArray(this);
		}
	}
	void Delete() {
		if (this.Entity <= MaxClients || !IsValidOwner(this.Owner)) {
			return;
		}
		int index = g_aProjectiles[this.Owner].FindValue(this.Entity);
		if (index != -1) {
			g_aProjectiles[this.Owner].Erase(index);
		}
		index = g_aVPhysicsList.FindValue(this.Entity);
		if (index != -1) {
			g_aVPhysicsList.Erase(index);
		}
	}
	void AddToVPhysicsList() {
		if (this.Entity > MaxClients && IsValidEntity(this.Entity)) {
			g_aVPhysicsList.PushArray(this);
		}
	}
	void GetOrigin(float vec[3]) {
		vec[0] = this.Origin[0];
		vec[1] = this.Origin[1];
		vec[2] = this.Origin[2];
	}
	void SetOrigin(float vec[3]) {
		this.Origin[0] = vec[0];
		this.Origin[1] = vec[1];
		this.Origin[2] = vec[2];
	}
	void GetAngles(float vec[3]) {
		vec[0] = this.Angles[0];
		vec[1] = this.Angles[1];
		vec[2] = this.Angles[2];
	}
	void SetAngles(float vec[3]) {
		this.Angles[0] = vec[0];
		this.Angles[1] = vec[1];
		this.Angles[2] = vec[2];
	}
	void GetVelocity(float vec[3]) {
		vec[0] = this.Velocity[0];
		vec[1] = this.Velocity[1];
		vec[2] = this.Velocity[2];
	}
	void SetVelocity(float vec[3]) {
		this.Velocity[0] = vec[0];
		this.Velocity[1] = vec[1];
		this.Velocity[2] = vec[2];
	}
}

// ================= SM API

public void OnPluginStart() {
	CreateConVar("sm_stasis_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD).SetString(PLUGIN_VERSION);

	RegAdminCmd("sm_stasis", cmdStasis, ADMFLAG_RESERVATION);

	HookEvent("player_team", eventPlayerStatusChange);
	HookEvent("player_changeclass", eventPlayerStatusChange);
	HookEvent("player_death", eventPlayerStatusChange);
	HookEvent("player_disconnect", eventPlayerStatusChange);

	g_aVPhysicsList = new ArrayList(sizeof(Projectile));

	for (int i = 1; i <= MaxClients; i++) {
		g_aProjectiles[i] = new ArrayList(sizeof(Projectile));
	}
}

public void OnMapStart() {
	g_iBeamSprite = PrecacheModel("sprites/laser.vmt", true);
	g_iHaloSprite = PrecacheModel("sprites/halo01.vmt", true);

	g_aVPhysicsList.Clear();

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
	int len = g_aVPhysicsList.Length;
	if (!len) {
		return;
	}
	for (int i = 0; i < len; i++) {
		Projectile p;
		g_aVPhysicsList.GetArray(i, p, sizeof(Projectile));

		int entity = p.Entity;
		int owner = p.Owner;

		if (!IsValidEntity(entity) || !IsValidOwner(owner) || !IsClientInStasis(owner)) {
			continue;
		}

		if (p.ExplodeTime) {
			int tick = GetEntProp(entity, Prop_Data, "m_nNextThinkTick");
			SetEntProp(entity, Prop_Data, "m_nNextThinkTick", tick+1);			
		}

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
	if (StrContains(classname, "tf_projectile") != -1) {
		DataPack dp = new DataPack();
		dp.WriteCell(entity);
		dp.WriteString(classname);
		dp.Reset();
		RequestFrame(frameProjectileSpawn, dp);
	}
}

public void OnEntityDestroyed(int entity) {
	Projectile p;
	p = FindProjectile(entity);
	if (!p.IsNull) {
		p.Delete();
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

	g_bStasis[client] = false;
	g_fStasisTick[client] = 0.0;
	g_iPauseTick[client] = 0;

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
	ScaleVector(vForward, GetVectorLength(g_vVelocity[client])*0.2);

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
	int count = g_aProjectiles[client].Length;
	if (!count) {
		return;
	}
	for (int i = 0; i < count; i++) {
		Projectile p;
		g_aProjectiles[client].GetArray(i, p, sizeof(Projectile));

		if (!IsValidEntity(p.Entity)) {
			p.Delete();
			return;
		}

		FreezeProjectile(client, p);

		// Variables changed - Update in array
		g_aProjectiles[client].SetArray(i, p, sizeof(Projectile));
	}

	g_iPauseTick[client] = GetGameTickCount();
}

void UnfreezeProjectiles(int client) {
	int count = g_aProjectiles[client].Length;
	if (!count) {
		return;
	}
	for (int i = 0; i < count; i++) {
		Projectile p;
		g_aProjectiles[client].GetArray(i, p, sizeof(Projectile));

		if (!IsValidEntity(p.Entity)) {
			p.Delete();
			return;
		}

		UnfreezeProjectile(client, p);

		// Variables changed - Update in array
		g_aProjectiles[client].SetArray(i, p, sizeof(Projectile));
	}
}

void FreezeProjectile(int client, Projectile p) {
	int entity = p.Entity;

	float origin[3];
	Entity_GetAbsOrigin(entity, origin);
	p.SetOrigin(origin);

	float angles[3];
	Entity_GetAbsAngles(entity, angles);
	p.SetAngles(angles);

	float velocity[3];
	Entity_GetAbsVelocity(entity, velocity);
	p.SetVelocity(velocity);

	p.Movetype = GetEntityMoveType(entity);

	// Projectile velocity laser
	float temp[3];
	GetVectorAngles(velocity, temp);

	float vForward[3];
	float vUp[3];
	float vRight[3];
	GetAngleVectors(temp, vForward, vUp, vRight);

	ScaleVector(vForward, GetVectorLength(velocity)*0.1);
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
	//	TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, ZeroVector());
}

void UnfreezeProjectile(int client, Projectile p) {
	int entity = p.Entity;

	MoveType movetype = p.Movetype;
	SetEntityMoveType(entity, movetype);

	float origin[3];
	p.GetOrigin(origin);

	float angles[3];
	p.GetAngles(angles);

	float velocity[3];
	p.GetVelocity(velocity);
	
	TeleportEntity(entity, origin, angles, velocity);

	int tick = p.ExplodeTime;
	if (tick) {
		// Calculate nextthink for pipe lifespan
		int spentticks = g_iPauseTick[client] - tick;
		int remainingticks = PIPE_TICKS_UNTIL_EXPLODE - spentticks;
		int newnextthink =  GetGameTickCount() + remainingticks;

		SetEntProp(entity, Prop_Data, "m_nNextThinkTick", newnextthink);

		// Account for the delay from stasis
		tick += GetGameTickCount()-g_iPauseTick[client];
		p.ExplodeTime = tick;
	}
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

int[] FindProjectile(int entity) {
	Projectile p;
	int owner = GetEntityOwner(entity);
	if (!IsValidOwner(owner)) {
		p.IsNull = true;
		return p;
	}

	int len;
	if (!(len = g_aProjectiles[owner].Length)) {
		p.IsNull = true;
		return p;
	}
	
	for (int i = 0; i < len; i++) {
		g_aProjectiles[owner].GetArray(i, p, sizeof(p));
		if (p.Owner == owner) {
			return p;
		}
	}

	p.IsNull = true;
	return p;
}

// -- Misc/Stocks

bool IsValidOwner(int owner) {
	return 0 < owner <= MaxClients;
}

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

void frameProjectileSpawn(DataPack dp) {
	int entity = dp.ReadCell();

	Projectile p;
	if (!p.SetEntity(entity) || !p.FindOwner()) {
		return;
	}

	char classname[64];
	dp.ReadString(classname, sizeof(classname));
	delete dp;

	if (StrEqual(classname, "tf_projectile_pipe") || StrContains(classname, "projectile_jar") != -1) {
		// Get tick count of spawn - used to perform calculations for lifespan
		p.ExplodeTime = GetGameTickCount();
		p.AddToVPhysicsList();
	}
	else if (StrEqual(classname, "tf_projectile_pipe_remote")) {
		p.AddToVPhysicsList();
	}

	p.Save();
}