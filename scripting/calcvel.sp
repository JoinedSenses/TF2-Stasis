#include <sourcemod>
#include <sdkhooks>

ArrayList g_aCalculate;
StringMap g_smProjectileLastTickOrigin;

public void OnPluginStart() {
	g_aCalculate = new ArrayList(6);
	g_smProjectileLastTickOrigin = new StringMap();

	RegAdminCmd("sm_countcalc", cmdCount, ADMFLAG_ROOT);
}

public Action cmdCount(int client, int args) {
	PrintToChat(client, "%i %i", g_aCalculate.Length, g_smProjectileLastTickOrigin.Size);
}

public void OnMapStart() {
	g_aCalculate.Clear();
	g_smProjectileLastTickOrigin.Clear();
}

public void OnEntityCreated(int entity, const char[] classname) {
	RequestFrame(frameSpawn, entity);
}

public void OnEntityDestroyed(int entity) {
	int index = -1
	if ((index = g_aCalculate.FindValue(entity)) != -1) {
		g_aCalculate.Erase(index);
		char sEntity[5];
		Format(sEntity, sizeof(sEntity), "%i", entity);
		g_smProjectileLastTickOrigin.Remove(sEntity);
	}
}

void frameSpawn(int entity) {
	if (!IsValidEntity(entity) || GetEntityMoveType(entity) != MOVETYPE_VPHYSICS || !HasEntProp(entity, Prop_Send, "m_vecOrigin")) {
		return;
	}

	PerformCalculations(entity);

	char sEntity[5];
	Format(sEntity, sizeof(sEntity), "%i", entity);

	float origin[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);

	g_smProjectileLastTickOrigin.SetArray(sEntity, origin, sizeof(origin));
}

void PerformCalculations(int entity) {
	g_aCalculate.Push(entity);
}

public void OnGameFrame() {
	if (g_aCalculate.Length < 1) {
		return;
	}
	for (int i = 0; i < g_aCalculate.Length; i++) {
		int entity = g_aCalculate.Get(i);

		if (!IsValidEdict(entity)) {
			continue;
		}

		if (!HasEntProp(entity, Prop_Send, "m_vecOrigin")) {
			g_aCalculate.Erase(i--);
			continue;
		}

		char sEntity[5];
		Format(sEntity, sizeof(sEntity), "%i", entity);

		float originOld[3];
		g_smProjectileLastTickOrigin.GetArray(sEntity, originOld, sizeof(originOld));

		float origin[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);

		float velocity[3];
		GetVelocity(originOld, origin, GetTickInterval(), velocity);

		SetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", velocity);

		g_smProjectileLastTickOrigin.SetArray(sEntity, origin, sizeof(origin));
	}
}

void GetVelocity(float previous[3], float current[3], float delta, float out[3]) {
    for (int i = 0; i < 3; i++) {
    	out[i] = (current[i] - previous[i])/delta;
    }
}