#define MAX_MODEL_SIZE 128

#define SOLID_VPHYSICS 6
#define COLLISION_GROUP_PLAYER 5

//Goofy ahh parent.
#define EF_NODRAW 32
#define EF_BONEMERGE 1
#define EF_BONEMERGE_FASTCULL 128
#define EF_PARENT_ANIMATES 512

#define EFFECT_KEY "m_fEffects"

void SetNoDraw(int ent, bool set) {
	int effects = GetEntProp(ent, Prop_Data, EFFECT_KEY);

	if(set) {
		effects |= EF_NODRAW;
	}
	else
	{
		effects &= ~EF_NODRAW;
	}

	SetEntProp(ent, Prop_Send, EFFECT_KEY, effects);
}

void SetParent(int child, int parent) {
    AcceptEntityInput(child, "SetParent", parent);
    SetEntProp(child, Prop_Send, EFFECT_KEY, EF_BONEMERGE|EF_BONEMERGE_FASTCULL|EF_PARENT_ANIMATES);
}

void RemoveParent(int child) {
    int effects = GetEntProp(child, Prop_Data, EFFECT_KEY);
    
    effects &= ~(EF_BONEMERGE|EF_BONEMERGE_FASTCULL|EF_PARENT_ANIMATES);

    AcceptEntityInput(child, "ClearParent");
    SetEntProp(child, Prop_Send, EFFECT_KEY, effects);
}

public int CreateRagdollBasedOnPlayer(int client) {
    //Try to get player model.
    char modelName[MAX_MODEL_SIZE];
    GetClientModel(client, modelName, MAX_MODEL_SIZE);

    //Setup ragdoll.
    int ragdoll = CreateEntityByName("prop_ragdoll");
    DispatchKeyValue(ragdoll, "model", modelName);

    //Set this as the player will collide with the doll.
    SetEntProp(ragdoll, Prop_Data, "m_nSolidType", SOLID_VPHYSICS);
    SetEntProp(ragdoll, Prop_Data, "m_CollisionGroup", COLLISION_GROUP_PLAYER);

    ActivateEntity(ragdoll);
    SetParent(ragdoll, client);

    return ragdoll;
}