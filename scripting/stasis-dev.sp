/*
 * This version requires SM 1.10 due to it using enum structs
 */

#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>

#define PIPE_TICKS_UNTIL_EXPLODE 145
#define SLOTCOUNT 3
#define PLUGIN_VERSION "1.0.3-dev"
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

Handle g_hCleanupTimer[MAXPLAYERS+1];

int g_iBeamSprite;
int g_iHaloSprite;

enum struct Player {
	int client;
	float origin[3];
	float velocity[3];
	float nextAttackPrimary[SLOTCOUNT];
	float nextAttackSecondary[SLOTCOUNT];
	float stasisTick;
	int pauseTick;
	int buttons;
	bool isInStasis;

	void toggleStasis() {
		if (!this.isInStasis) {
			this.enableStasis();
		}
		else {
			this.disableStasis();
		}
	}

	void enableStasis() {
		this.isInStasis = true;
		this.freeze();
		this.pauseAttack();
		this.displayLasers();
	}

	void disableStasis() {
		this.isInStasis = false;
		this.unfreeze();
		this.resumeAttack();
	}

	void freeze() {
		int client = this.client;

		freezeProjectiles(client);

		GetClientAbsOrigin(client, this.origin);

		getClientAbsVelocity(client, this.velocity);

		SetEntityMoveType(client, MOVETYPE_NONE);

		this.stasisTick = GetGameTime();
		this.buttons = GetClientButtons(client);
	}

	void unfreeze() {
		int client = this.client;

		unfreezeProjectiles(client);

		SetEntityMoveType(client, MOVETYPE_WALK);

		TeleportEntity(client, this.origin, NULL_VECTOR, this.velocity);	
	}

	void pauseAttack() {
		for (int slot = 0; slot < SLOTCOUNT; slot++) {
			int weapon = GetPlayerWeaponSlot(this.client, slot);
			if (!IsValidEntity(weapon)) {
				return;
			}

			if (HasEntProp(weapon, Prop_Send, "m_flNextPrimaryAttack")) {
				this.nextAttackPrimary[slot] = GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack");
				SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", 999999999.0);
			}

			if (HasEntProp(weapon, Prop_Send, "m_flNextSecondaryAttack")) {
				this.nextAttackSecondary[slot] = GetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack");
				SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", 999999999.0);
			}
		}
	}

	void resumeAttack() {
		for (int slot = 0; slot < SLOTCOUNT; slot++) {
			int weapon = GetPlayerWeaponSlot(this.client, slot);
			if (!IsValidEntity(weapon)) {
				return;
			}
			
			if (HasEntProp(weapon, Prop_Send, "m_flNextPrimaryAttack")) {
				SetEntPropFloat(
					  weapon
					, Prop_Send
					, "m_flNextPrimaryAttack"
					, this.nextAttackPrimary[slot]+(GetGameTime()-this.stasisTick)
				);
			}
			if (HasEntProp(weapon, Prop_Send, "m_flNextSecondaryAttack")) {
				SetEntPropFloat(
					  weapon
					, Prop_Send
					, "m_flNextSecondaryAttack"
					, this.nextAttackSecondary[slot]+(GetGameTime()-this.stasisTick)
				);	
			}
		}
	}

	void displayLasers() {
		int client = this.client;

		float angles[3];
		GetClientEyeAngles(client, angles);

		float eyePos[3];
		GetClientEyePosition(client, eyePos);

		float temp[3];
		GetVectorAngles(this.velocity, temp);

		float fwrd[3];
		GetAngleVectors(temp, fwrd, NULL_VECTOR, NULL_VECTOR);
		ScaleVector(fwrd, GetVectorLength(this.velocity)*0.2);
		AddVectors(this.origin, fwrd, temp);
		doLaserBeam(client, this.origin, temp);

		GetAngleVectors(angles, fwrd, NULL_VECTOR, NULL_VECTOR);
		ScaleVector(fwrd, 80.0);

		float end[3];
		AddVectors(eyePos, fwrd, end);
		doLaserBeam(client, eyePos, end, 255, 20, 20);

		temp = eyePos;
		temp[2] -= 30.0;
		doLaserBeam(client, temp, end, 255, 20, 20);
	}
}

Player player[MAXPLAYERS+1], DEFAULTSTATUS;

enum struct Projectile {
	int entity;
	int owner;
	bool isNull;
	float origin[3];
	float angles[3];
	float velocity[3];
	MoveType moveType;
	int explodeTime;

	bool setEntity(int entity) {
		if (entity > MaxClients && IsValidEntity(entity)) {
			this.entity = entity;
			return true;
		}
		return false;
	}

	int findOwner() {
		return (this.owner = getEntityOwner(this.entity));
	}

	void save() {
		if (this.entity > MaxClients && IsValidEntity(this.entity) && isValidOwner(this.owner)) {
			g_aProjectiles[this.owner].PushArray(this);
		}
	}

	void remove() {
		if (this.entity <= MaxClients || !isValidOwner(this.owner)) {
			return;
		}

		int index = g_aProjectiles[this.owner].FindValue(this.entity);
		if (index != -1) {
			g_aProjectiles[this.owner].Erase(index);
		}
		index = g_aVPhysicsList.FindValue(this.entity);
		if (index != -1) {
			g_aVPhysicsList.Erase(index);
		}
	}

	void addToVPhysicsList() {
		if (this.entity > MaxClients && IsValidEntity(this.entity)) {
			g_aVPhysicsList.PushArray(this);
		}
	}

	void freeze() {
		int entity = this.entity;

		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", this.origin);
		GetEntPropVector(entity, Prop_Data, "m_angAbsRotation", this.angles);
		GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", this.velocity);

		this.moveType = GetEntityMoveType(entity);

		SetEntityMoveType(this.entity, MOVETYPE_NONE);	
	}

	void unfreeze() {
		int entity = this.entity;

		SetEntityMoveType(entity, this.moveType);

		TeleportEntity(entity, this.origin, this.angles, this.velocity);

		this.updateExplodeTime();
	}

	void displayLasers() {
		int owner = this.owner;

		float temp[3];
		GetVectorAngles(this.velocity, temp);

		float fwrd[3];
		float up[3];
		float right[3];
		GetAngleVectors(temp, fwrd, up, right);

		ScaleVector(fwrd, GetVectorLength(this.velocity)*0.1);
		SubtractVectors(this.origin, fwrd, temp);
		doLaserBeam(owner, this.origin, temp, 50, 50);

		ScaleVector(up, 15.0);
		AddVectors(this.origin, up, temp);
		float temp2[3];
		SubtractVectors(this.origin, up, temp2);
		doLaserBeam(owner, temp2, temp, 100, 50);

		ScaleVector(right, 15.0);
		AddVectors(this.origin, right, temp);
		SubtractVectors(this.origin, right, temp2);
		doLaserBeam(owner, temp, temp2, 100, 50);
	}

	void updateExplodeTime() {
		int tick = this.explodeTime;
		if (tick) {
			int owner = this.owner;
			int spentTicks = player[owner].pauseTick - tick;
			int remainingTicks = PIPE_TICKS_UNTIL_EXPLODE - spentTicks;
			int newNextThink = GetGameTickCount() + remainingTicks;

			SetEntProp(this.entity, Prop_Data, "m_nNextThinkTick", newNextThink);

			tick += GetGameTickCount() - player[owner].pauseTick;
			this.explodeTime = tick;
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
		resetValues(i);

		if (isValidClient(i) && CheckCommandAccess(i, "sm_stasis", ADMFLAG_RESERVATION)) {
			g_hCleanupTimer[i] = CreateTimer(15.0, timerCleanup, GetClientUserId(i), TIMER_REPEAT);
		}
	}
}

public void OnClientConnected(int client) {
	if (!IsFakeClient(client) && CheckCommandAccess(client, "sm_stasis", ADMFLAG_RESERVATION)) {
		player[client].client = client;

		g_hCleanupTimer[client] = CreateTimer(15.0, timerCleanup, GetClientUserId(client), TIMER_REPEAT);
	}
}

public void OnClientDisconnect(int client) {
	delete g_hCleanupTimer[client];
}

public void eventPlayerStatusChange(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (client && !IsFakeClient(client) && CheckCommandAccess(client, "sm_stasis", ADMFLAG_RESERVATION)) {
		resetValues(client);
	}
}

public void OnPluginEnd() {
	for (int i = 1; i <= MaxClients; i++) {
		if (isValidClient(i) && isClientInStasis(i)) {
			player[i].disableStasis();
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
	if (!projectile.setEntity(entity) || !projectile.findOwner() || !CheckCommandAccess(projectile.owner, "sm_stasis", ADMFLAG_RESERVATION)) {
		delete dp;
		return;
	}

	char classname[64];
	dp.ReadString(classname, sizeof(classname));
	delete dp;

	if (StrEqual(classname, "tf_projectile_pipe") || StrContains(classname, "projectile_jar") != -1) {
		// Get tick count of spawn - used to perform calculations for lifespan
		projectile.explodeTime = GetGameTickCount();
		projectile.addToVPhysicsList();
	}
	else if (StrEqual(classname, "tf_projectile_pipe_remote")) {
		projectile.addToVPhysicsList();
	}

	projectile.save();
}

public void OnEntityDestroyed(int entity) {
	Projectile projectile;
	projectile = findProjectile(entity);

	if (!projectile.isNull) {
		projectile.remove();
	}
}

// ================= Commands

public Action cmdStasis(int client, int args) {
	if (!client || IsClientObserver(client) || GetEntityMoveType(client) == MOVETYPE_NOCLIP) {
		return Plugin_Handled;
	}
	// Restriction until stable for all classes
	TFClassType class = TF2_GetPlayerClass(client);
	if (class != TFClass_Soldier && class != TFClass_DemoMan) {
		PrintToChat(client, "Unsupported class");
		return Plugin_Handled;
	}

	player[client].toggleStasis();
	return Plugin_Handled;
}

// ================= Internal Functions

// -- Timer

Action timerCleanup(Handle timer, int userid) {
	// Cleanup to check for valid projectiles
	int client = GetClientOfUserId(userid);

	if (!client) {
		return Plugin_Stop;
	}

	if (g_aProjectiles[client].Length) {
		for (int i = 0; i < g_aProjectiles[client].Length; i++) {
			Projectile projectile;
			g_aProjectiles[client].GetArray(i, projectile, sizeof(Projectile));

			int entity = projectile.entity;

			if (!IsValidEntity(entity)) {
				g_aProjectiles[client].Erase(i--);
				continue;
			}

			char classname[32];
			GetEntityClassname(entity, classname, sizeof(classname));

			if (StrContains(classname, "tf_projectile") == -1) {
				g_aProjectiles[client].Erase(i--);
			}
		}
	}

	if (g_aVPhysicsList.Length) {
		for (int i = 0; i < g_aVPhysicsList.Length; i++) {
			Projectile projectile;
			g_aVPhysicsList.GetArray(i, projectile, sizeof(Projectile));

			int entity = projectile.entity;

			if (!IsValidEntity(entity)) {
				g_aVPhysicsList.Erase(i--);
				continue;
			}

			char classname[32];
			GetEntityClassname(entity, classname, sizeof(classname));

			if (StrContains(classname, "tf_projectile") == -1) {
				g_aVPhysicsList.Erase(i--);
			}
		}		
	}

	return Plugin_Continue;
}

// -- Client

void resetValues(int client) {
	g_aProjectiles[client].Clear();
	player[client] = DEFAULTSTATUS;
	player[client].client = client;
}

bool isValidClient(int client) {
	return ((0 < client <= MaxClients) && IsClientInGame(client) && !IsFakeClient(client));
}

bool isValidOwner(int owner) {
	return 0 < owner <= MaxClients;
}

bool isClientInStasis(int client) {
	return player[client].isInStasis;
}

// -- Projectiles

void freezeProjectiles(int client) {
	int count = g_aProjectiles[client].Length;
	if (!count) {
		return;
	}
	for (int i = 0; i < count; i++) {
		Projectile projectile;
		g_aProjectiles[client].GetArray(i, projectile, sizeof(Projectile));

		if (!IsValidEntity(projectile.entity)) {
			projectile.remove();
			return;
		}

		projectile.freeze();
		projectile.displayLasers();

		// Variables changed - Update in array
		g_aProjectiles[client].SetArray(i, projectile, sizeof(Projectile));
	}

	player[client].pauseTick = GetGameTickCount();
}

void unfreezeProjectiles(int client) {
	int count = g_aProjectiles[client].Length;
	if (!count) {
		return;
	}

	for (int i = 0; i < count; i++) {
		Projectile projectile;
		g_aProjectiles[client].GetArray(i, projectile, sizeof(Projectile));

		if (!IsValidEntity(projectile.entity)) {
			projectile.remove();
			return;
		}

		projectile.unfreeze();

		// Variables changed - Update in array
		g_aProjectiles[client].SetArray(i, projectile, sizeof(Projectile));
	}
}

// -- Entity

int getEntityOwner(int entity) {
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

Projectile[] findProjectile(int entity) {
	Projectile projectile;
	int owner = getEntityOwner(entity);
	if (!isValidOwner(owner)) {
		projectile.isNull = true;
		return projectile;
	}

	int len;
	if (!(len = g_aProjectiles[owner].Length)) {
		projectile.isNull = true;
		return projectile;
	}
	
	for (int i = 0; i < len; i++) {
		g_aProjectiles[owner].GetArray(i, projectile, sizeof(projectile));
		if (projectile.owner == owner) {
			return projectile;
		}
	}

	projectile.isNull = true;
	return projectile;
}

// -- Misc/Stocks

void doLaserBeam(int client, float start[3], float end[3], int r = 255, int g = 255, int b = 255, int a = 255) {
	int color[4];
	color[0] = r;
	color[1] = g;
	color[2] = b;
	color[3] = a;
	TE_SetupBeamPoints(start, end, g_iBeamSprite, g_iHaloSprite, 0, 66, 10.0, 15.0, 15.0, 1, 1.0, color, 0);
	TE_SendToClient(client);
}

int getActiveWeapon(int client) {
	int weapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");

	if (!IsValidEntity(weapon)) {
		return INVALID_ENT_REFERENCE;
	}

	return weapon;
}

bool getClientAbsVelocity(int client, float velocity[3]) {
	static int offset = -1;
	
	if (offset == -1 && (offset = FindDataMapInfo(client, "m_vecAbsVelocity")) == -1) {
		velocity = NULL_VECTOR;
		return false;
	}
	
	GetEntDataVector(client, offset, velocity);
	return true;
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

		int entity = projectile.entity;
		int owner = projectile.owner;

		if (!IsValidEntity(entity) || !isValidOwner(owner) || !isClientInStasis(owner)) {
			continue;
		}

		if (projectile.explodeTime) {
			int tick = GetEntProp(entity, Prop_Data, "m_nNextThinkTick");
			SetEntProp(entity, Prop_Data, "m_nNextThinkTick", tick+1);
		}

		// Some dumb method of preventing vphysics entites from getting stuck in the air by keeping them "moving".
		static float fakeVelocity[3] = {0.001, 0.001, 0.001};
		TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, fakeVelocity);
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	if (!isClientInStasis(client)) {
		return Plugin_Continue;
	}

	Action action = Plugin_Continue;
	switch (TF2_GetPlayerClass(client)) {
		case TFClass_Soldier, TFClass_Medic: {
			buttons &= ~IN_ATTACK;
			return Plugin_Changed;
		}
		case TFClass_DemoMan: {
			int playerWeapon = getActiveWeapon(client);
			if (playerWeapon == INVALID_ENT_REFERENCE) {
				return Plugin_Continue;
			}

			char classname[64];
			GetEntityClassname(playerWeapon, classname, sizeof(classname));

			if (StrEqual(classname, "tf_weapon_pipebomblauncher")) {
				float startTime = GetEntPropFloat(playerWeapon, Prop_Send, "m_flChargeBeginTime");
				if (startTime) {
					// Hold sticky charge if it has began
					SetEntPropFloat(playerWeapon, Prop_Send, "m_flChargeBeginTime", startTime+GetTickInterval());
				}
			}
			else if (StrEqual(classname, "tf_weapon_cannon")) {
				float detTime = GetEntPropFloat(playerWeapon, Prop_Send, "m_flDetonateTime");
				if (detTime) {
					SetEntPropFloat(playerWeapon, Prop_Send, "m_flDetonateTime", detTime+GetTickInterval());
					//SetEntProp(playerweapon, Prop_Send, "m_nSequence", 0);
					//PrintToChatAll("%0.2f", GetEntPropFloat(playerWeapon, Prop_Send, "m_flPlaybackRate"));
				}
			}
		}
		case TFClass_Heavy: {
			if (player[client].buttons & IN_ATTACK2) {
				buttons |= IN_ATTACK2;
				action = Plugin_Changed;
			}
		}
		case TFClass_Sniper: {
			int playerWeapon = getActiveWeapon(client);
			if (playerWeapon == INVALID_ENT_REFERENCE) {
				return Plugin_Continue;
			}

			char classname[64];
			GetEntityClassname(playerWeapon, classname, sizeof(classname));

			if (!StrEqual(classname, "tf_weapon_compound_bow")) {
				return Plugin_Continue;
			}

			float startTime = GetEntPropFloat(playerWeapon, Prop_Send, "m_flChargeBeginTime");
			if (startTime) {
				SetEntPropFloat(playerWeapon, Prop_Send, "m_flChargeBeginTime", startTime+GetTickInterval());
			}
		}
	}

	if (player[client].buttons & IN_ATTACK) {
		buttons |= IN_ATTACK;
		action = Plugin_Changed;
	}

	return action;
}