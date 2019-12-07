#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#define MAX_NET_ENTS 2048

public Plugin myinfo = {
	name = "VPhysics CalcVel",
	author = "JoinedSenses",
	description = "Calculates velocity of vphysics and sets m_vecAbsVelocity",
	version = "1.0.1",
	url = "http://github.com/JoinedSenses"
};

enum struct Projectile {
	int entRef;
	float origin[3];
}

ArrayList g_aProjectiles;
float g_fTickInterval;

public void OnPluginStart() {
	g_aProjectiles = new ArrayList(sizeof(Projectile));
	g_fTickInterval = GetTickInterval();
}

public void OnMapStart() {
	g_aProjectiles.Clear();
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (entity <= MaxClients || entity > MAX_NET_ENTS) {
		return;
	}

	RequestFrame(frameSpawn, EntIndexToEntRef(entity));
}

public void OnEntityDestroyed(int entity) {
	if (entity <= MaxClients) {
		return;
	}

	int index = g_aProjectiles.FindValue(EntIndexToEntRef(entity));
	if (index != -1) {
		g_aProjectiles.Erase(index);
	}
}

void frameSpawn(int entRef) {
	int entity = EntRefToEntIndex(entRef);
	if (entity <= MaxClients || GetEntityMoveType(entity) != MOVETYPE_VPHYSICS || !HasEntProp(entity, Prop_Send, "m_vecOrigin")) {
		return;
	}

	Projectile p;
	p.entRef = EntIndexToEntRef(entity);
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", p.origin);

	g_aProjectiles.PushArray(p);
}

public void OnGameFrame() {
	Projectile p;
	int len = g_aProjectiles.Length;
	for (int i = 0; i < len; i++) {
		g_aProjectiles.GetArray(i, p);
		int entity = EntRefToEntIndex(p.entRef);
		if (entity <= MaxClients) {
			continue;
		}

		float origin[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);

		float velocity[3];
		GetVelocity(p.origin, origin, g_fTickInterval, velocity);
		SetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", velocity);

		p.origin = origin;
		g_aProjectiles.SetArray(i, p);
	}
}

void GetVelocity(float previous[3], float current[3], float delta, float out[3]) {
    for (int i = 0; i < 3; i++) {
    	out[i] = (current[i] - previous[i])/delta;
    }
}