#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>

#define PIPE_TICKS_UNTIL_EXPLODE 145
#define PLUGIN_VERSION "1.0.0"
#define PLUGIN_DESCRIPTION "Stasis: A state which does not change"

enum {
	SLOT1,
	SLOT2,
	SLOT3
}

enum {
	PRIMARY,
	SECONDARY
}

float g_vOrigin[MAXPLAYERS+1][3];
float g_vVelocity[MAXPLAYERS+1][3];
float g_vForwardVel[MAXPLAYERS+1][3];

float g_fNextAttack[MAXPLAYERS+1][3][2];
float g_fStasisTick[MAXPLAYERS+1];

bool g_bStasis[MAXPLAYERS+1];

int g_iBeamSprite;
int g_iHaloSprite;

ArrayList g_aProjectiles[MAXPLAYERS+1];
ArrayList g_aCalculate;

StringMap g_smProjectileOrigin[MAXPLAYERS+1];
StringMap g_smProjectileOriginLastTick[MAXPLAYERS+1];
StringMap g_smProjectileAngles[MAXPLAYERS+1];
StringMap g_smProjectileVelocity[MAXPLAYERS+1];

StringMap g_smProjectileExplodeTime[MAXPLAYERS+1];

int g_iOldTick[MAXPLAYERS+1];

public Plugin myinfo = {
	name = "Stasis",
	author = "JoinedSenses",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "http://github.com/JoinedSenses"
};

public void OnPluginStart() {
	CreateConVar("sm_stasis_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD).SetString(PLUGIN_VERSION);

	RegAdminCmd("sm_stasis", cmdStasis, ADMFLAG_RESERVATION);

	g_aCalculate = new ArrayList(6);

	for (int i = 1; i <= MaxClients; i++) {
		g_aProjectiles[i] = new ArrayList(6);
		g_smProjectileOrigin[i] = new StringMap();
		g_smProjectileOriginLastTick[i] = new StringMap();
		g_smProjectileAngles[i] = new StringMap();
		g_smProjectileVelocity[i] = new StringMap();
		g_smProjectileExplodeTime[i] = new StringMap();
	}
}

public void OnMapStart() {
	g_iBeamSprite = PrecacheModel("sprites/laser.vmt", true);
	g_iHaloSprite = PrecacheModel("sprites/halo01.vmt", true);

	g_aCalculate.Clear();

	for (int i = 1; i <= MaxClients; i++) {
		g_aProjectiles[i].Clear();
		g_smProjectileOrigin[i].Clear();
		g_smProjectileOriginLastTick[i].Clear();
		g_smProjectileAngles[i].Clear();
		g_smProjectileVelocity[i].Clear();
		g_smProjectileExplodeTime[i].Clear();
	}
}

public void OnGameFrame() {
	if (g_aCalculate.Length < 1) {
		return;
	}
	// ArrayList of pipes/stickies
	for (int i = 0; i < g_aCalculate.Length; i++) {
		int entity = g_aCalculate.Get(i);

		if (!IsValidEntity(entity)) {
			continue;
		}

		int owner = HasEntProp(entity, Prop_Send, "m_hThrower") ? GetEntPropEnt(entity, Prop_Send, "m_hThrower") : -1;
		if (!IsValidClient(owner)) {
			continue;
		}

		char sEntity[5];
		Format(sEntity, sizeof(sEntity), "%i", entity);

		if (!IsClientInStasis(owner)) {
			// Game doesn't set velocity prop for pipes fow whatever reason, so I am calculating it and setting it.
			float originOld[3];
			g_smProjectileOriginLastTick[owner].GetArray(sEntity, originOld, sizeof(originOld));

			float origin[3];
			Entity_GetAbsOrigin(entity, origin);

			float velocity[3];
			GetVelocity(originOld, origin, GetTickInterval(), velocity);

			Entity_SetAbsVelocity(entity, velocity);

			g_smProjectileOriginLastTick[owner].SetArray(sEntity, origin, sizeof(origin));
		}
		else {
			// Checking if this is a pipe grenade
			int trash;
			if (g_smProjectileExplodeTime[owner].GetValue(sEntity, trash)) {
				int tick = GetEntProp(entity, Prop_Data, "m_nNextThinkTick");
				SetEntProp(entity, Prop_Data, "m_nNextThinkTick", tick+1);
			}
			else {
				// Some dumb method of preventing stickies from getting stuck in the air by keeping them "moving".
				float fakevelocity[3] = {0.001, 0.001, 0.001};
				TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, fakevelocity);
			}
		}
	}
}

public Action cmdStasis(int client, int args) {
	if (!client) {
		return Plugin_Handled;
	}
	TFClassType class = TF2_GetPlayerClass(client);
	if (class != TFClass_Soldier && class != TFClass_DemoMan) {
		PrintToChat(client, "Unsupported class");
		return Plugin_Handled;
	}
	int slot1 = GetPlayerWeaponSlot(client,0);
	int slot2 = GetPlayerWeaponSlot(client,1);
	int slot3 = GetPlayerWeaponSlot(client,2);

	FreezeProjectilesPost(client);

	if (!IsClientInStasis(client)) {
		// Store velocity/origin and create laser
		GetClientAbsVelocity(client, g_vVelocity[client]);

		float temp[3];
		GetVectorAngles(g_vVelocity[client], temp);
		GetAngleVectors(temp, g_vForwardVel[client], NULL_VECTOR, NULL_VECTOR);
		ScaleVector(g_vForwardVel[client], GetVectorLength(g_vVelocity[client])*0.4);

		GetClientAbsOrigin(client, g_vOrigin[client]);
		AddVectors(g_vOrigin[client], g_vForwardVel[client], temp);

		TE_SetupBeamPoints(g_vOrigin[client], temp, g_iBeamSprite, g_iHaloSprite, 0, 66, 10.0, 20.0, 20.0, 1, 1.0, {255, 255, 255, 255}, 0);
		TE_SendToAll();

		// Get eye angles and create laser
		float vEyeAngles[3];
		GetClientEyeAngles(client, vEyeAngles);

		float vForward[3];
		GetAngleVectors(vEyeAngles, vForward, NULL_VECTOR, NULL_VECTOR);
		ScaleVector(vForward, 100.0);

		float vEyepos[3];
		GetClientEyePosition(client, vEyepos);
		AddVectors(vEyepos, vForward, vEyepos);

		temp = vEyepos;
		temp[2] -= 20.0;
		TE_SetupBeamPoints(temp, vEyepos, g_iBeamSprite, g_iHaloSprite, 0, 66, 10.0, 20.0, 20.0, 1, 1.0, {255, 50, 50, 255}, 0);
		TE_SendToAll();

		// Freeze client
		SetEntityMoveType(client, MOVETYPE_NONE);

		// Calculations for when client can attack again
		g_fStasisTick[client] = GetGameTime();

		if (IsValidEntity(slot1)) {
			g_fNextAttack[client][SLOT1][PRIMARY] = GetEntPropFloat(slot1, Prop_Send, "m_flNextPrimaryAttack");
			SetEntPropFloat(slot1, Prop_Send, "m_flNextPrimaryAttack", 999999999.0);
		}

		if (IsValidEntity(slot2)) {
			g_fNextAttack[client][SLOT2][PRIMARY] = GetEntPropFloat(slot2, Prop_Send, "m_flNextPrimaryAttack");
			SetEntPropFloat(slot2, Prop_Send, "m_flNextPrimaryAttack", 999999999.0);

			g_fNextAttack[client][SLOT2][SECONDARY] = GetEntPropFloat(slot2, Prop_Send, "m_flNextSecondaryAttack");
			SetEntPropFloat(slot2, Prop_Send, "m_flNextSecondaryAttack", 999999999.0);
		}

		if (IsValidEntity(slot3)) {
			g_fNextAttack[client][SLOT3][PRIMARY] = GetEntPropFloat(slot3, Prop_Send, "m_flNextPrimaryAttack");
			SetEntPropFloat(slot3, Prop_Send, "m_flNextPrimaryAttack", 999999999.0);
		}
	}
			
	else {
		// Unfreeze client
		SetEntityMoveType(client, MOVETYPE_WALK);
		TeleportEntity(client, g_vOrigin[client], NULL_VECTOR, g_vVelocity[client]);

		// Restore attack
		if (IsValidEntity(slot1)) {
			SetEntPropFloat(slot1, Prop_Send, "m_flNextPrimaryAttack", g_fNextAttack[client][SLOT1][PRIMARY]+(GetGameTime()-g_fStasisTick[client]));
		}
		if (IsValidEntity(slot2)) {
			SetEntPropFloat(slot2, Prop_Send, "m_flNextPrimaryAttack", g_fNextAttack[client][SLOT2][PRIMARY]+(GetGameTime()-g_fStasisTick[client]));
			SetEntPropFloat(slot2, Prop_Send, "m_flNextSecondaryAttack", g_fNextAttack[client][SLOT2][SECONDARY]+(GetGameTime()-g_fStasisTick[client]));
		}
		if (IsValidEntity(slot3)) {
			SetEntPropFloat(slot3, Prop_Send, "m_flNextPrimaryAttack", g_fNextAttack[client][SLOT3][PRIMARY]+(GetGameTime()-g_fStasisTick[client]));
		}
	}

	// Toggle
	g_bStasis[client] = !g_bStasis[client];

	return Plugin_Handled;
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (StrEqual(classname, "tf_projectile_rocket")) {
		RequestFrame(frameSpawnRocket, entity);
	}
	else if (StrContains(classname, "projectile_pipe") != -1) {
		RequestFrame(frameSpawnPipe, entity);
		g_aCalculate.Push(entity);
	}
}

public void frameSpawnRocket(int entity) {
	int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if (!(0 < owner <= MaxClients)) {
		return;
	}
	// ArrayList of client's projectiles
	g_aProjectiles[owner].Push(entity);
}

public void frameSpawnPipe(int entity) {
	int owner = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
	if (!(0 < owner <= MaxClients) || !IsValidEntity(entity)) {
		return;
	}
	// ArrayList of client's projectiles
	g_aProjectiles[owner].Push(entity);

	char sEntity[5];
	Format(sEntity, sizeof(sEntity), "%i", entity);

	float origin[3];
	Entity_GetAbsOrigin(entity, origin);

	// Store origin - used to calculate velocity during OnGameFrame
	g_smProjectileOriginLastTick[owner].SetArray(sEntity, origin, sizeof(origin));

	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));

	if (StrEqual(classname, "tf_projectile_pipe")) {
		// Get tick count of spawn - used to perform calculations for lifespan
		g_smProjectileExplodeTime[owner].SetValue(sEntity, GetGameTickCount());
	}
}

public void OnEntityDestroyed(int entity) {
	// Clear arrays/stringmaps when entity is destroyed
	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));

	bool rocket;
	if ((rocket = StrEqual(classname, "tf_projectile_rocket")) || StrContains(classname, "projectile_pipe") != -1) {
		int owner = GetEntPropEnt(entity, Prop_Send, rocket ? "m_hOwnerEntity" : "m_hThrower");
		if (!(0 < owner <= MaxClients)) {
			return;
		}

		int index;
		if ((index = g_aProjectiles[owner].FindValue(entity)) != -1) {
			g_aProjectiles[owner].Erase(index);
		}
		if ((index = g_aCalculate.FindValue(entity)) != -1) {
			g_aCalculate.Erase(index);
		}

		char sEntity[5];
		Format(sEntity, sizeof(sEntity), "%i", entity);

		g_smProjectileOrigin[owner].Remove(sEntity);
		g_smProjectileOriginLastTick[owner].Remove(sEntity);
		g_smProjectileAngles[owner].Remove(sEntity);
		g_smProjectileVelocity[owner].Remove(sEntity);
		g_smProjectileExplodeTime[owner].Remove(sEntity);
	}
}

void FreezeProjectilesPost(int client) {
	if (g_aProjectiles[client].Length) {
		for (int i = 0; i < g_aProjectiles[client].Length; i++) {
			int entity = g_aProjectiles[client].Get(i);

			char sEntity[5];
			Format(sEntity, sizeof(sEntity), "%i", entity);

			char classname[64];
			GetEntityClassname(entity, classname, sizeof(classname));

			bool rocket = StrEqual(classname, "tf_projectile_rocket");

			float origin[3];
			float angles[3];
			float velocity[3];

			if (IsClientInStasis(client)) {
				// EXIT STASIS
				g_smProjectileOrigin[client].GetArray(sEntity, origin, sizeof(origin));
				g_smProjectileAngles[client].GetArray(sEntity, angles, sizeof(angles));
				g_smProjectileVelocity[client].GetArray(sEntity, velocity, sizeof(velocity));

				SetEntityMoveType(entity, rocket ? MOVETYPE_FLY : MOVETYPE_VPHYSICS);
				TeleportEntity(entity, origin, angles, velocity);

				int tick;
				bool result = g_smProjectileExplodeTime[client].GetValue(sEntity, tick);

				if (result) {
					// Calculate nextthink for pipe lifespan
					int spentticks = g_iOldTick[client] - tick;
					int remainingticks = PIPE_TICKS_UNTIL_EXPLODE - spentticks;
					int newnextthink =  GetGameTickCount() + remainingticks;

					SetEntProp(entity, Prop_Data, "m_nNextThinkTick", newnextthink);
				}
			}
			else {
				// ENTER STASIS
				Entity_GetAbsOrigin(entity, origin);
				g_smProjectileOrigin[client].SetArray(sEntity, origin, sizeof(origin));

				Entity_GetAbsAngles(entity, angles);
				g_smProjectileAngles[client].SetArray(sEntity, angles, sizeof(angles));

				Entity_GetAbsVelocity(entity, velocity);
				g_smProjectileVelocity[client].SetArray(sEntity, velocity, sizeof(velocity));

				// Projectile velocity laser
				float temp[3];
				GetVectorAngles(velocity, temp);

				float forwardvel[3];
				GetAngleVectors(temp, forwardvel, NULL_VECTOR, NULL_VECTOR);
				ScaleVector(forwardvel, GetVectorLength(forwardvel)*150.0);

				AddVectors(origin, forwardvel, temp);

				TE_SetupBeamPoints(origin, temp, g_iBeamSprite, g_iHaloSprite, 0, 66, 10.0, 15.0, 15.0, 1, 1.0, {50, 50, 255, 255}, 0);
				TE_SendToAll();
				///////

				SetEntityMoveType(entity, MOVETYPE_NONE);
				TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, ZeroVector());

				g_iOldTick[client] = GetGameTickCount();
			}
		}
	}
}

bool IsValidClient(int client) {
	return ((0 < client <= MaxClients) && IsClientInGame(client));
}

bool IsClientInStasis(int client) {
	return g_bStasis[client];
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

void Entity_SetAbsVelocity(int entity, const float vec[3]) {
	SetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", vec);
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

void GetVelocity(float previous[3], float current[3], float delta, float out[3]) {
    for (int i = 0; i < 3; i++) {
    	out[i] = (current[i] - previous[i])/delta;
    }
}