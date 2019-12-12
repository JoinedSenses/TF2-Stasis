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
#define PLUGIN_VERSION "2.0.1-dev"
#define PLUGIN_DESCRIPTION "Stasis: A state which does not change"
#define MAX_NET_ENTS 2048

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

enum struct Player {
	int userID;
	float origin[3];
	float velocity[3];
	float nextAttackPrimary[SLOTCOUNT];
	float nextAttackSecondary[SLOTCOUNT];
	float stasisTick;
	int pauseTick;
	int buttons;
	bool isInStasis;

	int get() {
		return GetClientOfUserId(this.userID);
	}

	void set(int client) {
		this.userID = isValidClient(client) ? GetClientUserId(client) : 0;
	}

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
		int client = this.get();
		if (!client) {
			return;
		}

		freezeProjectiles(client);

		GetClientAbsOrigin(client, this.origin);

		getClientAbsVelocity(client, this.velocity);

		SetEntityMoveType(client, MOVETYPE_NONE);

		this.stasisTick = GetGameTime();
		this.buttons = GetClientButtons(client);
		this.pauseTick = GetGameTickCount();
	}

	void unfreeze() {
		int client = this.get();
		if (!client) {
			return;
		}

		unfreezeProjectiles(client);

		SetEntityMoveType(client, MOVETYPE_WALK);

		TeleportEntity(client, this.origin, NULL_VECTOR, this.velocity);	
	}

	void pauseAttack() {
		int client = this.get();
		if (!client) {
			return;
		}

		for (int slot = 0; slot < SLOTCOUNT; slot++) {
			int weapon = GetPlayerWeaponSlot(client, slot);
			if (!IsValidEntity(weapon)) {
				continue;
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
		int client = this.get();
		if (!client) {
			return;
		}

		for (int slot = 0; slot < SLOTCOUNT; slot++) {
			int weapon = GetPlayerWeaponSlot(client, slot);
			if (!IsValidEntity(weapon)) {
				continue;
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
		int client = this.get();
		if (!client) {
			return;
		}

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

Player player[MAXPLAYERS+1];

Player[] defaultPlayer(int client) {
	Player p;
	p.set(client);
	return p;
}

enum struct Projectile {
	int entRef;
	int ownerUserID;
	float origin[3];
	float angles[3];
	float velocity[3];
	MoveType moveType;
	int explodeTime;

	int getEntity() {
		return EntRefToEntIndex(this.entRef);
	}

	bool setEntity(int entity) {
		if (IsValidEntity(entity)) {
			if (entity < -1 || entity > MAX_NET_ENTS) {
				this.entRef = entity;
			}
			else {
				this.entRef = EntIndexToEntRef(entity);
			}
			return true;
		}
		return false;
	}

	int getOwner() {
		return GetClientOfUserId(this.ownerUserID);
	}

	bool setOwner(int client) {
		if (isValidClient(client) && CheckCommandAccess(client, "sm_stasis", ADMFLAG_RESERVATION)) {
			this.ownerUserID = GetClientUserId(client);
			return true;
		}
		return false;
	}

	void save() {
		if (this.getEntity()) {
			int owner = this.getOwner();	
			if (isValidOwner(owner)) {
				g_aProjectiles[owner].PushArray(this);
			}
		}
	}

	void addToVPhysicsList() {
		if (this.getEntity()) {
			g_aVPhysicsList.PushArray(this);
		}
	}

	void freeze() {
		int entity = this.getEntity();
		if (!entity) {
			return;
		}

		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", this.origin);
		GetEntPropVector(entity, Prop_Data, "m_angAbsRotation", this.angles);
		GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", this.velocity);

		this.moveType = GetEntityMoveType(entity);

		SetEntityMoveType(entity, MOVETYPE_NONE);	
	}

	void unfreeze() {
		int entity = this.getEntity();
		if (!entity) {
			return;
		}

		SetEntityMoveType(entity, this.moveType);

		TeleportEntity(entity, this.origin, this.angles, this.velocity);

		this.updateExplodeTime();
	}

	void displayLasers() {
		int owner = this.getOwner();
		if (!isValidOwner(owner)) {
			return;
		}

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
		int entity = this.getEntity();
		if (!entity) {
			return;
		}

		int tick = this.explodeTime;
		if (tick) {
			int owner = this.getOwner();
			if (owner) {
				int spentTicks = player[owner].pauseTick - tick;
				int remainingTicks = PIPE_TICKS_UNTIL_EXPLODE - spentTicks;
				int newNextThink = GetGameTickCount() + remainingTicks;

				SetEntProp(entity, Prop_Data, "m_nNextThinkTick", newNextThink);

				tick += GetGameTickCount() - player[owner].pauseTick;
				this.explodeTime = tick;
			}
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

		if (IsClientInGame(i)) {
			OnClientConnected(i);
		}
	}
}

public void OnMapStart() {
	g_iBeamSprite = PrecacheModel("sprites/laser.vmt", true);
	g_iHaloSprite = PrecacheModel("sprites/halo01.vmt", true);

	g_aVPhysicsList.Clear();
}

public void OnClientConnected(int client) {
	if (!IsFakeClient(client) && CheckCommandAccess(client, "sm_stasis", ADMFLAG_RESERVATION)) {
		player[client] = defaultPlayer(client);
	}
}

public void OnClientDisconnect(int client) {
	g_aProjectiles[client].Clear();
}

public void eventPlayerStatusChange(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (isValidClient(client) && CheckCommandAccess(client, "sm_stasis", ADMFLAG_RESERVATION)) {
		g_aProjectiles[client].Clear();
		player[client] = defaultPlayer(client);
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
		dp.WriteCell(EntIndexToEntRef(entity));
		dp.WriteString(classname);
		dp.Reset();

		RequestFrame(frameProjectileSpawn, dp);
	}
}

void frameProjectileSpawn(DataPack dp) {
	int entity = EntRefToEntIndex(dp.ReadCell());
	if (entity <= MaxClients) {
		delete dp;
		return;
	}

	Projectile projectile;

	int owner = getEntityOwner(entity);
	if (!projectile.setOwner(owner)) {
		delete dp;
		return;
	}
	
	// this probably wont ever return false, entity has already been verified, but whatever.
	if (!projectile.setEntity(entity)) {
		delete dp;
		return;
	}

	char classname[64];
	dp.ReadString(classname, sizeof(classname));
	delete dp;

	bool isVPhysics = false;
	if (StrEqual(classname, "tf_projectile_pipe") || StrContains(classname, "projectile_jar") != -1) {
		// Get tick count of spawn - used to perform calculations for lifespan
		projectile.explodeTime = GetGameTickCount();
		isVPhysics = true;
	}
	else if (StrEqual(classname, "tf_projectile_pipe_remote")) {
		isVPhysics = true;
	}

	if (isClientInStasis(owner) || isVPhysics) {
		ArrayList al = new ArrayList(sizeof(Projectile));
		al.PushArray(projectile);
		al.Push(owner);
		al.Push(isVPhysics);

		// if vphysics, wait two frames, otherwise one frame
		RequestFrame(isVPhysics ? frameOne : frameTwo, al);
	}
	else {
		g_aProjectiles[owner].PushArray(projectile);
	}
}

public void frameOne(ArrayList al) {
	RequestFrame(frameTwo, al);
}

public void frameTwo(ArrayList al) {
	Projectile p;
	al.GetArray(0, p);
	int owner = al.Get(1);
	bool isVPhysics = al.Get(2);
	delete al;

	if (!p.getEntity()) {
		return;
	}

	if (isClientInStasis(owner)) {
		p.freeze();
		p.displayLasers();
	}

	if (isVPhysics) {
		g_aVPhysicsList.PushArray(p);
	}

	g_aProjectiles[owner].PushArray(p);
}

public void OnEntityDestroyed(int entity) {
	if (entity <= MaxClients || entity > MAX_NET_ENTS) {
		return;
	}

	int entRef = EntIndexToEntRef(entity);

	int index = g_aVPhysicsList.FindValue(entRef);
	if (index != -1) {
		g_aVPhysicsList.Erase(index);
	}

	int owner = getEntityOwner(entity);
	if (isValidOwner(owner)) {
		index = g_aProjectiles[owner].FindValue(entRef);
		if (index != -1) {
			g_aProjectiles[owner].Erase(index);
		}
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

// -- Client

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
	if (!isValidClient(client)) {
		return;
	}

	int count = g_aProjectiles[client].Length;
	if (!count) {
		return;
	}

	for (int i = 0; i < count; i++) {
		Projectile projectile;
		g_aProjectiles[client].GetArray(i, projectile, sizeof(Projectile));

		projectile.freeze();
		projectile.displayLasers();

		// Variables changed - Update in array
		g_aProjectiles[client].SetArray(i, projectile, sizeof(Projectile));
	}
}

void unfreezeProjectiles(int client) {
	int count = g_aProjectiles[client].Length;
	if (!count) {
		return;
	}

	for (int i = 0; i < count; i++) {
		Projectile projectile;
		g_aProjectiles[client].GetArray(i, projectile, sizeof(Projectile));

		projectile.unfreeze();

		// Variables changed - Update in array
		g_aProjectiles[client].SetArray(i, projectile, sizeof(Projectile));
	}
}

// -- Entity

int getEntityOwner(int entity) {
	if (entity <= MaxClients || !IsValidEntity(entity)) {
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

		int owner = projectile.getOwner();

		if (!isClientInStasis(owner)) {
			continue;
		}

		int entity = projectile.getEntity();

		if (projectile.explodeTime) {
			int tick = GetEntProp(entity, Prop_Data, "m_nNextThinkTick");
			SetEntProp(entity, Prop_Data, "m_nNextThinkTick", tick+1);
		}

		// Some dumb method of preventing vphysics entites from getting stuck in the air by keeping them "moving".
		static float fakeVelocity[3] = {0.001, 0.001, 0.001};
		TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, fakeVelocity);
	}
}

public Action OnPlayerRunCmd(int client, int &buttons) {
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