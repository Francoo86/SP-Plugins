#include <sdkhooks>
#include <sdktools>
#include <sourcemod>
#include <helpers.sp>

#pragma newdecls required
#pragma semicolon 1

float VECTOR_ORIGIN[3] = {0.0, 0.0, 0.0};

#define MAX_MODEL_SIZE 128
#define SOLID_VPHYSICS 6

#define COLLISION_GROUP_PLAYER 5
#define NULL_ACTIVATOR -1
#define NO_RAGDOLL -1

//Spectate thingy?
#define OBS_MODE_CHASE 5
#define OBS_MODE_NONE 0


#define MAX_PLAYERS 64

//Goofy ahh parent.
#define EF_NODRAW 32
//Parent bonemerging?.
#define EF_BONEMERGE 1
#define EF_BONEMERGE_FASTCULL 128
#define EF_PARENT_ANIMATES 512

//Internal keys.
#define ABS_VEL_KEY "m_vecAbsVelocity"
#define VELOCITY_KEY "m_vecVelocity"
#define POSITION_KEY "m_vecOrigin"

//PLS WORK
#define BASE_VELOCITY "m_vecBaseVelocity"

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

	GetEntPropVector(ragdoll, Prop_Data, POSITION_KEY, pos);
	SetEntPropVector(client, Prop_Send, POSITION_KEY, pos);

	GetEntPropVector(ragdoll, Prop_Data, VELOCITY_KEY, velocity);
	//Hope this works.
	SetEntPropVector(client, Prop_Send, VELOCITY_KEY, VECTOR_ORIGIN);

	AcceptEntityInput(client, "ClearParent");

	SetEntProp(client, Prop_Send, "m_iObserverMode", OBS_MODE_NONE);
	SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", NULL_ACTIVATOR);
	SetEntityMoveType(client, MOVETYPE_WALK);
	
	SetNoDraw(client, false);

	//Unqueue this thing.
	ActualDolls[client].ragdoll = NO_RAGDOLL;

	RemoveEntity(ragdoll);
}

public void PossessRagdoll(int client, int ragdoll) {
	//Shitty thing, why tf this doesn't work.
	SetEntPropVector(client, Prop_Send, VELOCITY_KEY, VECTOR_ORIGIN);
	SetEntPropVector(client, Prop_Data, BASE_VELOCITY, VECTOR_ORIGIN);

	SetEntityMoveType(client, MOVETYPE_OBSERVER);
	SetEntProp(client, Prop_Send, "m_iObserverMode", OBS_MODE_CHASE);
	SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", ragdoll);

	SetParent(client, ragdoll);
}

public void Ragdolize(int client) {
	int oldRagdoll = ActualDolls[client].ragdoll;

	if (!IsPlayerAlive(client)) {
		return;
	}

	if(oldRagdoll > 0) {
		Unragdolize(client);
		return;
	}

	float origin[3], velocity[3];

	int ragdoll = CreateRagdollBasedOnPlayer(client);
	GetClientAbsOrigin(client, origin);

	//Get Velocity.
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);

	origin[2] += 32;

	if(DispatchSpawn(ragdoll)) {
		//Stop parenting pls.
		RemoveParent(ragdoll);
		TeleportEntity(ragdoll, origin, NULL_VECTOR, velocity);

		SetEntProp(ragdoll, Prop_Data, "m_CollisionGroup", 0);
		AcceptEntityInput(ragdoll, "EnableMotion");
		SetEntityMoveType(ragdoll, MOVETYPE_VPHYSICS);

		PossessRagdoll(client, ragdoll);

		SetNoDraw(client, true);

		ActualDolls[client].ragdoll = ragdoll;
	}
}

public Action MakeRagdolls(int client, int varargs) {
	Ragdolize(client);

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