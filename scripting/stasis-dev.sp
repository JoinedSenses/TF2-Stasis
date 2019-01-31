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

ArrayList g_aProjectiles[MAXPLAYERS+1];
ArrayList g_aVPhysicsList;

int g_iBeamSprite;
int g_iHaloSprite;

enum {
	PRIMARYATTACK,
	SECONDARYATTACK
}

enum struct Player {
	int Client;
	float Origin[3];
	float Velocity[3];
	float NextAttackPrimary[SLOTCOUNT];
	float NextAttackSecondary[SLOTCOUNT];
	float StasisTick;
	int PauseTick;
	int Buttons;
	bool IsInStasis;

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
	void ToggleStasis() {
		if (!this.IsInStasis) {
			this.EnableStasis();
		}
		else {
			this.DisableStasis();
		}
	}
	void EnableStasis() {
		this.IsInStasis = true;
		this.Freeze();
		this.PauseAttack();
		this.DisplayLasers();
	}
	void DisableStasis() {
		this.IsInStasis = false;
		this.Unfreeze();
		this.ResumeAttack();
	}
	void Freeze() {
		int client = this.Client;

		FreezeProjectiles(client);

		float origin[3];
		GetClientAbsOrigin(client, origin);
		this.SetOrigin(origin);

		float velocity[3];
		GetClientAbsVelocity(client, velocity);
		this.SetVelocity(velocity);

		SetEntityMoveType(client, MOVETYPE_NONE);

		this.StasisTick = GetGameTime();
		this.Buttons = GetClientButtons(client);
	}
	void Unfreeze() {
		int client = this.Client;

		UnfreezeProjectiles(client);

		SetEntityMoveType(client, MOVETYPE_WALK);

		float origin[3];
		this.GetOrigin(origin);

		float velocity[3];
		this.GetVelocity(velocity);

		TeleportEntity(client, origin, NULL_VECTOR, velocity);	
	}
	void PauseAttack() {
		for (int slot = 0; slot < SLOTCOUNT; slot++) {
			int weapon = GetPlayerWeaponSlot(this.Client, slot);
			if (!IsValidEntity(weapon)) {
				return;
			}
			if (HasEntProp(weapon, Prop_Send, "m_flNextPrimaryAttack")) {
				this.NextAttackPrimary[slot] = GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack");
				SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", 999999999.0);
			}
			if (HasEntProp(weapon, Prop_Send, "m_flNextSecondaryAttack")) {
				this.NextAttackSecondary[slot] = GetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack");
				SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", 999999999.0);
			}
		}		
	}

	void ResumeAttack() {
		for (int slot = 0; slot < SLOTCOUNT; slot++) {
			int weapon = GetPlayerWeaponSlot(this.Client, slot);
			if (!IsValidEntity(weapon)) {
				return;
			}
			if (HasEntProp(weapon, Prop_Send, "m_flNextPrimaryAttack")) {
				SetEntPropFloat(
					  weapon
					, Prop_Send
					, "m_flNextPrimaryAttack"
					, this.NextAttackPrimary[slot]+(GetGameTime()-this.StasisTick)
				);
			}
			if (HasEntProp(weapon, Prop_Send, "m_flNextSecondaryAttack")) {
				SetEntPropFloat(
					  weapon
					, Prop_Send
					, "m_flNextSecondaryAttack"
					, this.NextAttackSecondary[slot]+(GetGameTime()-this.StasisTick)
				);	
			}
		}
	}
	void DisplayLasers() {
		int client = this.Client;

		float origin[3];
		this.GetOrigin(origin);

		float angles[3];
		GetClientEyeAngles(client, angles);

		float velocity[3];
		this.GetVelocity(velocity);

		float eyepos[3];
		GetClientEyePosition(client, eyepos);

		float temp[3];
		GetVectorAngles(velocity, temp);

		float fwrd[3];
		GetAngleVectors(temp, fwrd, NULL_VECTOR, NULL_VECTOR);
		ScaleVector(fwrd, GetVectorLength(velocity)*0.2);
		AddVectors(origin, fwrd, temp);
		LaserBeam(client, origin, temp);

		GetAngleVectors(angles, fwrd, NULL_VECTOR, NULL_VECTOR);
		ScaleVector(fwrd, 80.0);

		float end[3];
		AddVectors(eyepos, fwrd, end);
		LaserBeam(client, eyepos, end, 255, 20, 20);

		temp = eyepos;
		temp[2] -= 30.0;
		LaserBeam(client, temp, end, 255, 20, 20);
	}
}

Player player[MAXPLAYERS+1];
Player DEFAULTSTATUS;

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
	void Freeze() {
		int entity = this.Entity;

		float temp[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", temp);
		this.SetOrigin(temp);

		GetEntPropVector(entity, Prop_Data, "m_angAbsRotation", temp);
		this.SetAngles(temp);

		GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", temp);
		this.SetVelocity(temp);

		this.Movetype = GetEntityMoveType(entity);

		SetEntityMoveType(this.Entity, MOVETYPE_NONE);
		//	TeleportEntity(this.Entity, NULL_VECTOR, NULL_VECTOR, ZeroVector());	
	}
	void Unfreeze() {
		int entity = this.Entity;

		SetEntityMoveType(entity, this.Movetype);

		float origin[3];
		this.GetOrigin(origin);

		float angles[3];
		this.GetAngles(angles);

		float velocity[3];
		this.GetVelocity(velocity);

		TeleportEntity(entity, origin, angles, velocity);

		this.UpdateExplodeTime();
	}
	void DisplayLasers() {
		// TODO: FIX
		float origin[3];
		this.GetVelocity(origin);
		float velocity[3];
		this.GetVelocity(velocity);

		int owner = this.Owner;

		float temp[3];
		GetVectorAngles(velocity, temp);

		float fwrd[3];
		float up[3];
		float right[3];
		GetAngleVectors(temp, fwrd, up, right);

		ScaleVector(fwrd, GetVectorLength(velocity)*0.1);
		SubtractVectors(origin, fwrd, temp);
		LaserBeam(owner, origin, temp, 50, 50);

		ZeroVector(temp);
		ScaleVector(up, 15.0);
		AddVectors(origin, up, temp);
		float temp2[3];
		SubtractVectors(origin, up, temp2);
		LaserBeam(owner, temp2, temp, 100, 50);

		ZeroVector(temp);
		ZeroVector(temp2);
		ScaleVector(right, 15.0);
		AddVectors(origin, right, temp);
		SubtractVectors(origin, right, temp2);
		LaserBeam(owner, temp, temp2, 100, 50);
	}
	void UpdateExplodeTime() {
		int tick = this.ExplodeTime;
		if (tick) {
			int owner = this.Owner;
			int spentticks = player[owner].PauseTick - tick;
			int remainingticks = PIPE_TICKS_UNTIL_EXPLODE - spentticks;
			int newnextthink = GetGameTickCount() + remainingticks;

			SetEntProp(this.Entity, Prop_Data, "m_nNextThinkTick", newnextthink);

			tick += GetGameTickCount()-player[owner].PauseTick;
			this.ExplodeTime = tick;
		}
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

public void OnClientConnected(int client) {
	if (CheckCommandAccess(client, "sm_stasis", ADMFLAG_RESERVATION)) {
		player[client].Client = client;
	}
}

public Action eventPlayerStatusChange(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client && CheckCommandAccess(client, "sm_stasis", ADMFLAG_RESERVATION)) {
		ResetValues(client);
	}
}

public void OnPluginEnd() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsValidClient(i) && IsClientInStasis(i)) {
			player[i].DisableStasis();
			PrintToChat(i, "Stasis ending. Plugin reloading");
		}
	}
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

void frameProjectileSpawn(DataPack dp) {
	int entity = dp.ReadCell();

	Projectile projectile;
	if (!projectile.SetEntity(entity) || !projectile.FindOwner() || !CheckCommandAccess(projectile.Owner, "sm_stasis", ADMFLAG_RESERVATION)) {
		return;
	}

	char classname[64];
	dp.ReadString(classname, sizeof(classname));
	delete dp;

	if (StrEqual(classname, "tf_projectile_pipe") || StrContains(classname, "projectile_jar") != -1) {
		// Get tick count of spawn - used to perform calculations for lifespan
		projectile.ExplodeTime = GetGameTickCount();
		projectile.AddToVPhysicsList();
	}
	else if (StrEqual(classname, "tf_projectile_pipe_remote")) {
		projectile.AddToVPhysicsList();
	}

	projectile.Save();
}

public void OnEntityDestroyed(int entity) {
	Projectile projectile;
	projectile = FindProjectile(entity);
	if (!projectile.IsNull) {
		projectile.Delete();
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

	player[client].ToggleStasis();
	return Plugin_Handled;
}

// ================= Internal Functions

// -- Client

void ResetValues(int client) {
	g_aProjectiles[client].Clear();
	player[client] = DEFAULTSTATUS;
	player[client].Client = client;
}

bool IsValidClient(int client) {
	return ((0 < client <= MaxClients) && IsClientInGame(client));
}

bool IsValidOwner(int owner) {
	return 0 < owner <= MaxClients;
}

bool IsClientInStasis(int client) {
	return player[client].IsInStasis;
}

// -- Projectiles

void FreezeProjectiles(int client) {
	int count = g_aProjectiles[client].Length;
	if (!count) {
		return;
	}
	for (int i = 0; i < count; i++) {
		Projectile projectile;
		g_aProjectiles[client].GetArray(i, projectile, sizeof(Projectile));

		if (!IsValidEntity(projectile.Entity)) {
			projectile.Delete();
			return;
		}

		projectile.Freeze();
		projectile.DisplayLasers();

		// Variables changed - Update in array
		g_aProjectiles[client].SetArray(i, projectile, sizeof(Projectile));
	}

	player[client].PauseTick = GetGameTickCount();
}

void UnfreezeProjectiles(int client) {
	int count = g_aProjectiles[client].Length;
	if (!count) {
		return;
	}
	for (int i = 0; i < count; i++) {
		Projectile projectile;
		g_aProjectiles[client].GetArray(i, projectile, sizeof(Projectile));

		if (!IsValidEntity(projectile.Entity)) {
			projectile.Delete();
			return;
		}

		projectile.Unfreeze();

		// Variables changed - Update in array
		g_aProjectiles[client].SetArray(i, projectile, sizeof(Projectile));
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
	Projectile projectile;
	int owner = GetEntityOwner(entity);
	if (!IsValidOwner(owner)) {
		projectile.IsNull = true;
		return projectile;
	}

	int len;
	if (!(len = g_aProjectiles[owner].Length)) {
		projectile.IsNull = true;
		return projectile;
	}
	
	for (int i = 0; i < len; i++) {
		g_aProjectiles[owner].GetArray(i, projectile, sizeof(projectile));
		if (projectile.Owner == owner) {
			return projectile;
		}
	}

	projectile.IsNull = true;
	return projectile;
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

int GetActiveWeapon(int client) {
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

float[] ZeroVector(float vec[3] = NULL_VECTOR) {
	vec[0] = vec[1] = vec[2] = 0.0;
	return vec;
}

// ================= Game Frame Logic

public void OnGameFrame() {
	int len = g_aVPhysicsList.Length;
	if (!len) {
		return;
	}
	for (int i = 0; i < len; i++) {
		Projectile projectile;
		g_aVPhysicsList.GetArray(i, projectile, sizeof(Projectile));

		int entity = projectile.Entity;
		int owner = projectile.Owner;

		if (!IsValidEntity(entity) || !IsValidOwner(owner) || !IsClientInStasis(owner)) {
			continue;
		}

		if (projectile.ExplodeTime) {
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

	Action action = Plugin_Continue;
	switch (TF2_GetPlayerClass(client)) {
		case TFClass_Soldier, TFClass_Medic: {
			return Plugin_Continue;
		}
		case TFClass_DemoMan: {
			int playerweapon;
			if ((playerweapon = GetActiveWeapon(client)) == INVALID_ENT_REFERENCE) {
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
			if (player[client].Buttons & IN_ATTACK2) {
				buttons |= IN_ATTACK2;
				action = Plugin_Changed;
			}
		}
		case TFClass_Sniper: {
			int playerweapon;
			if ((playerweapon = GetActiveWeapon(client)) == INVALID_ENT_REFERENCE) {
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

	if (player[client].Buttons & IN_ATTACK) {
		buttons |= IN_ATTACK;
		action = Plugin_Changed;
	}

	return action;
}