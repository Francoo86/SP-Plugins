#include <sdkhooks>
#include <sdktools>
#include <sourcemod>

#pragma newdecls required
#pragma semicolon 1

#define MAX_MODEL_SIZE 128
#define SOLID_VPHYSICS 6

#define COLLISION_GROUP_PLAYER 5
#define NULL_ACTIVATOR -1
#define NO_RAGDOLL -1

//Spectate thingy?
#define OBS_MODE_CHASE 5
#define OBS_MODE_NONE 0

#define EF_NODRAW 32

#define MAX_PLAYERS 64

//Parent bonemerging?.
#define EF_BONEMERGE 1
#define EF_BONEMERGE_FASTCULL 128
#define EF_PARENT_ANIMATES 512

float VECTOR_ORIGIN[3] = {0.0, 0.0, 0.0};

public Plugin myinfo =
{
	name = "SP-Plugins",
	author = "Francoo86",
	description = "[REDACTED]",
	version = "1.0.0",
	url = "https://github.com/Francoo86/SP-Plugins"
};

enum struct RagdollData {
	int ragdoll;
}

RagdollData ActualDolls[MAX_PLAYERS + 1];

public bool IsRagdoll(int client) {
	return ActualDolls[client].ragdoll > 0;
}

public void Unragdolize(int client){
	float pos[3], velocity[3];
	int ragdoll = ActualDolls[client].ragdoll;

	if (ragdoll == 0 && !IsValidEntity(ragdoll)) {
		ActualDolls[client].ragdoll = NO_RAGDOLL;
		return;
	}

	GetEntPropVector(ragdoll, Prop_Data, "m_vecOrigin", pos);
	SetEntPropVector(client, Prop_Send, "m_vecOrigin", pos);

	GetEntPropVector(ragdoll, Prop_Data, "m_vecVelocity", velocity);
	SetEntPropVector(client, Prop_Data, "m_vecVelocity", VECTOR_ORIGIN);

	AcceptEntityInput(client, "ClearParent");

	SetEntProp(client, Prop_Send, "m_iObserverMode", OBS_MODE_NONE);
	SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", NULL_ACTIVATOR);
	SetEntityMoveType(client, MOVETYPE_WALK);
	
	int effects = GetEntProp(client, Prop_Data, "m_fEffects");
	SetEntProp(client, Prop_Send, "m_fEffects", effects - EF_NODRAW);

	//Unqueue this thing.
	ActualDolls[client].ragdoll = NO_RAGDOLL;

	RemoveEntity(ragdoll);
}

public void PossessRagdoll(int client, int ragdoll) {
	SetEntProp(client, Prop_Send, "m_iObserverMode", OBS_MODE_CHASE);
	SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", ragdoll);
	SetEntityMoveType(client, MOVETYPE_OBSERVER);
	AcceptEntityInput(client, "SetParent", ragdoll);
}

public void Ragdolize(int client) {

}

public Action MakeRagdolls(int client, int varargs) {
	int oldRagdoll = ActualDolls[client].ragdoll;

	if (!IsPlayerAlive(client)) {
		return Plugin_Handled;
	}

	if(oldRagdoll > 0) {
		Unragdolize(client);

		return Plugin_Handled;
	}

	//Try to get player model.
	char modelName[MAX_MODEL_SIZE];
	GetClientModel(client, modelName, MAX_MODEL_SIZE);
	PrecacheModel(modelName);

	//Setup ragdoll.
	int ragdoll = CreateEntityByName("prop_ragdoll");
	DispatchKeyValue(ragdoll, "model", modelName);


	float origin[3], velocity[3];

	GetClientAbsOrigin(client, origin);

	//Get Velocity.
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);

	//Shitty thing.
	SetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", VECTOR_ORIGIN);

	PrintToChat(client, "The actual velocity length is: %0.2f", GetVectorLength(velocity));

	SetEntProp(ragdoll, Prop_Data, "m_nSolidType", SOLID_VPHYSICS);
	SetEntProp(ragdoll, Prop_Data, "m_CollisionGroup", COLLISION_GROUP_PLAYER);
	SetEntityMoveType(ragdoll, MOVETYPE_NONE);

	AcceptEntityInput(ragdoll, "SetParent", client, client);
	SetEntProp(ragdoll, Prop_Send, "m_fEffects", EF_BONEMERGE|EF_BONEMERGE_FASTCULL|EF_PARENT_ANIMATES);

	ActivateEntity(ragdoll);

	origin[2] += 32;

	if(DispatchSpawn(ragdoll)) {
		//Stop parenting pls.
		AcceptEntityInput(ragdoll, "ClearParent");

		TeleportEntity(ragdoll, origin, NULL_VECTOR, velocity);

		SetEntProp(ragdoll, Prop_Data, "m_CollisionGroup", 0);
		AcceptEntityInput(ragdoll, "EnableMotion");
		SetEntityMoveType(ragdoll, MOVETYPE_VPHYSICS);

		PossessRagdoll(client, ragdoll);

		int effects = GetEntProp(client, Prop_Data, "m_fEffects");
		SetEntProp(client, Prop_Send, "m_fEffects", effects + EF_NODRAW);

		ActualDolls[client].ragdoll = ragdoll;
	}

	return Plugin_Handled;
}

void RemoveGoofyDoll(int client){
	int oldRagdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");

	if(IsValidEdict(oldRagdoll)){
		RemoveEntity(oldRagdoll);
	}
}

Action PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid")); // Get Player's userid
	if (ActualDolls[client].ragdoll > 0) {
		RequestFrame(RemoveGoofyDoll, client);
	}

	return Plugin_Continue;
}

Action PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid")); // Get Player's userid
	if (ActualDolls[client].ragdoll > 0) {
		Unragdolize(client);
	}

	return Plugin_Continue;
}

//TODO: Disable spec changing.
//Avoid problems with spectators.
public void TryToEnforceRagdoll(int client) {
	int spec = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
	int ragdoll = ActualDolls[client].ragdoll;

	if (ragdoll > 0 && (spec != ragdoll)) {
		PossessRagdoll(client, ragdoll);
	}
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], 
int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	int isPressing = mouse[0] || mouse[1];

	if (isPressing) {
		TryToEnforceRagdoll(client);
	}

	return Plugin_Continue;
}


public void OnPluginStart()
{
	RegConsoleCmd("sm_test_entity", MakeRagdolls, "Some interesting test...");
	HookEvent("player_death", PlayerDeath);
	HookEvent("player_spawn", PlayerSpawn);
}