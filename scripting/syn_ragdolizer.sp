#include <sdkhooks>
#include <sdktools>
#include <sourcemod>
#include <syn_helpers.sp>

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

Handle CreateServerRagdoll;

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
	int FOV;
	float lastTime;
}

RagdollData ActualDolls[MAX_PLAYERS + 1];

Handle FOVConVar;

public bool IsRagdoll(int client) {
	return ActualDolls[client].ragdoll > 0;
}

public void Unragdolize(int client){
	float pos[3], velocity[3];
	int ragdoll = ActualDolls[client].ragdoll;

	if (ragdoll <= 0) {
		ActualDolls[client].ragdoll = NO_RAGDOLL;
		return;
	}

	GetEntPropVector(ragdoll, Prop_Data, POSITION_KEY, pos);
	SetEntPropVector(client, Prop_Send, POSITION_KEY, pos);

	GetEntPropVector(ragdoll, Prop_Data, VELOCITY_KEY, velocity);
	//Enforce 0 Velocity.
	SetEntPropVector(client, Prop_Data, VELOCITY_KEY, VECTOR_ORIGIN);
	SetEntPropVector(client, Prop_Data, BASE_VELOCITY, VECTOR_ORIGIN);

	AcceptEntityInput(client, "ClearParent");

	SetEntProp(client, Prop_Send, "m_iObserverMode", OBS_MODE_NONE);
	SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", NULL_ACTIVATOR);
	SetEntityMoveType(client, MOVETYPE_WALK);
	
	SetNoDraw(client, false);

	SetFOV(client, ActualDolls[client].FOV);

	//Unqueue this thing.
	ActualDolls[client].ragdoll = NO_RAGDOLL;

	RemoveEntity(ragdoll);
}

public void PossessRagdoll(int client, int ragdoll) {
	//Shitty thing, why tf this doesn't work.
	SetEntPropVector(client, Prop_Data, VELOCITY_KEY, VECTOR_ORIGIN);
	SetEntPropVector(client, Prop_Data, BASE_VELOCITY, VECTOR_ORIGIN);

	SetEntityMoveType(client, MOVETYPE_OBSERVER);
	SetEntProp(client, Prop_Send, "m_iObserverMode", OBS_MODE_CHASE);
	SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", ragdoll);

	SetParent(client, ragdoll);

	SetNoDraw(client, true);
	SetFOV(client, GetConVarInt(FOVConVar));
}

void Ragdolize(int client, bool onDeath = false) {
	if (!IsPlayerAlive(client) && !onDeath) {
		return;
	}

	static MemoryBlock damage;

	if (damage == null)
		damage = new MemoryBlock(0x4C);

	int forceBone = 0;

	if(onDeath)
		forceBone = GetEntProp(client, Prop_Send, "m_nForceBone");

	int ragdoll = SDKCall(CreateServerRagdoll, client, forceBone, damage.Address, 3, false);
	SetupRagdollForUse(client, ragdoll);
}

void SetupRagdollForUse(int client, int ragdoll) {
	int actualFov = GetFOV(client);
	ActualDolls[client].FOV = actualFov;
	PossessRagdoll(client, ragdoll);

	SetFOV(client, GetConVarInt(FOVConVar));

	ActualDolls[client].ragdoll = ragdoll;
}

public Action HandleRagdolling(int client, int varargs) {
	if (!IsPlayerAlive(client)) {
		return Plugin_Continue;
	}

	if (!IsRagdoll(client)) {
		Ragdolize(client);
	}
	else {
		Unragdolize(client);
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
	else {
		//TODO: Convarize.
		Ragdolize(client, true);
		//Don't create cl dolls.
		RequestFrame(RemoveGoofyDoll, client);

		ActualDolls[client].lastTime = GetGameTime() + 4;
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
	int ragdoll = ActualDolls[client].ragdoll;

	//Player should be alive for this checking.
	if (IsPlayerAlive(client) && (ragdoll > 0)) {
		int spec = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

		if (spec != ragdoll) {
			PossessRagdoll(client, ragdoll);
		}
	}
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3]
, int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]){
	if(!IsRagdoll(client)) {
		return Plugin_Continue;
	}

	if (IsPlayerAlive(client) && (buttons & IN_WALK)) {
		buttons &= ~IN_WALK;
		Unragdolize(client);
	}

	return Plugin_Changed;
}

void LoadMethods() {
	GameData data = new GameData("syn_server");
	if(data == null) {
		SetFailState("Can't load the HL2DM methods.");
		return;
	}

	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(data, SDKConf_Signature, "CreateServerRagdoll");
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer); 
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);       
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_ByRef);      
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);       
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);               
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);

	delete data;

	CreateServerRagdoll = EndPrepSDKCall();
}

public void OnPluginStart()
{
	RegConsoleCmd("sm_ragdolize", HandleRagdolling, "Ragdolizes yourself.");
	FOVConVar = CreateConVar("sm_ragdoll_fov", "45", "Sets the FOV for ragdolizing.", FCVAR_REPLICATED | FCVAR_SERVER_CAN_EXECUTE);

	HookEvent("player_death", PlayerDeath);
	HookEvent("player_spawn", PlayerSpawn);

	LoadMethods();
}

public void OnGameFrame() {
	for(int client = 1; client <= MaxClients; client++){
		if (!IsClientInGame(client)) continue;

		TryToEnforceRagdoll(client);
	}
}