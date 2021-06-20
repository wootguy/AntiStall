// TODO:
// - trains ans stuff
// - fake survival
// - disable hud
// - op4 boss damage not counted

void print(string text) { g_Game.AlertMessage( at_console, text); }
void println(string text) { print(text + "\n"); }

dictionary g_player_states;
dictionary g_monster_blacklist; // boring monsters that can't possibly be exciting
dictionary g_toggle_ents; // entities that trigger things (buttons, doors, etc.)

array<array<array<uint32>>> g_visited_zones;
array<ExcitementEnt> g_excitement_ents;

const int ZONES_PER_AXIS = 128;
const Vector MIN_ZONE_COORDS = Vector(-32768, -32768, -32768);
const float ZONE_SIZE = abs(MIN_ZONE_COORDS.x*2) / ZONES_PER_AXIS;
const int MAX_EXCITEMENT = 120;

float g_excitement; // how interesting the game is to watch (0-100)
bool g_is_boring; // is excitement at 0?
bool g_is_kinda_boring; // excitement levels low but not dangerously low
float g_last_kinda_boring;

class ExcitementEnt {
	EHandle h_ent;
	float lastHealth;
	bool isKillable = false;
	bool isToggleEnt = false;
	bool everUsed = false;
	bool wasAlive = true;
	int oldToggleState = 0;
	string name;
	
	ExcitementEnt() {}
	
	ExcitementEnt(EHandle h_ent) {
		this.h_ent = h_ent;
		name = h_ent.GetEntity().pev.classname;
		
		if (g_toggle_ents.exists(name)) {
			isToggleEnt = true;
			oldToggleState = h_ent.GetEntity().GetToggleState();
		} else {
			isKillable = true;
			wasAlive = true;
		}
	}
}

class PlayerState {
	bool debug = false;
	bool wasAlive = true;

	PlayerState() {}
	
	float checkExcitement(CBasePlayer@ plr) {		
		float newExcitement = 0;
		
		Vector zoneCoords = plr.pev.origin - MIN_ZONE_COORDS;
		
		int zoneX = int(zoneCoords.x / ZONE_SIZE);
		int zoneY = int(zoneCoords.y / ZONE_SIZE);
		int zoneZ = int(zoneCoords.z / ZONE_SIZE);
		
		if (zoneX < 0 or zoneX >= ZONES_PER_AXIS or zoneY < 0 or zoneY >= ZONES_PER_AXIS or zoneZ < 0 or zoneZ >= ZONES_PER_AXIS) {
			println("ZONE OUT OF BOUNDS");
		} else if (plr.IsAlive()) {			
			if (g_visited_zones[zoneX][zoneY][zoneZ] & getPlayerBit(plr) == 0) {
				if (g_visited_zones[zoneX][zoneY][zoneZ] == 0) {
					newExcitement += 10;
					debugMessage("[AntiStall] New area explored by " + plr.pev.netname + "! +10 excitement\n");
				} else {
					newExcitement += 5;
					debugMessage("[AntiStall] " + plr.pev.netname + " hasn't been here yet! +5 excitement\n");
				}
				
				g_visited_zones[zoneX][zoneY][zoneZ] |= getPlayerBit(plr);
			} else {
				//println("ZONE " + zoneX + " " + zoneY + " " + zoneZ);
			}
		}
		
		if (plr.IsAlive() && !wasAlive) {
			newExcitement += 5;
			debugMessage("[AntiStall] " + plr.pev.netname + " was revived! +5 excitement\n");
		}
		
		wasAlive = plr.IsAlive();
		
		return newExcitement;
	}
}


void add_excitement_ent(CBaseEntity@ ent) {
	string cname = ent.pev.classname;
	
	if (isMonster(ent)) {
		if (g_monster_blacklist.exists(ent.pev.classname)) {
			return;
		}
		g_excitement_ents.insertLast(ExcitementEnt(EHandle(ent)));
	} else if (ent.IsBreakable()) {
		g_excitement_ents.insertLast(ExcitementEnt(EHandle(ent)));
	} else if (g_toggle_ents.exists(ent.pev.classname)) {
		g_excitement_ents.insertLast(ExcitementEnt(EHandle(ent)));
	}
}

bool isMonster(CBaseEntity@ ent) {
	string cname = ent.pev.classname;
	return (ent.IsMonster() && cname.Find("monster_") == 0) || cname.Find("geneworm_") == 0;
}

void reload_ents() {
	g_excitement_ents.resize(0);
	
	CBaseEntity@ent = null;
	do {
		@ent = g_EntityFuncs.FindEntityByClassname(ent, "*");
		if (ent !is null) {
			add_excitement_ent(ent);
		}
	} while(ent !is null);
}

HookReturnCode EntityCreated(CBaseEntity@ ent) {
	add_excitement_ent(ent);
	return HOOK_CONTINUE;
}

uint32 getPlayerBit(CBaseEntity@ plr) {
	return (1 << (plr.entindex() & 31));
}

void PluginInit() {
	g_Module.ScriptInfo.SetAuthor( "w00tguy" );
	g_Module.ScriptInfo.SetContactInfo( "https://github.com/wootguy" );
	
	g_Hooks.RegisterHook( Hooks::Game::EntityCreated, @EntityCreated );
	g_Hooks.RegisterHook( Hooks::Player::ClientSay, @ClientSay );
	
	g_Scheduler.SetInterval("update_excitement", 0.5f, -1);
	
	g_monster_blacklist["monster_barney_dead"] = true;
	g_monster_blacklist["monster_cockroach"] = true;
	g_monster_blacklist["monster_furniture"] = true;
	g_monster_blacklist["monster_handgrenade"] = true;
	g_monster_blacklist["monster_hevsuit_dead"] = true;
	g_monster_blacklist["monster_hgrunt_dead"] = true;
	g_monster_blacklist["monster_human_grunt_ally_dead"] = true;
	g_monster_blacklist["monster_leech"] = true;
	g_monster_blacklist["monster_otis_dead"] = true;
	g_monster_blacklist["monster_satchel"] = true;
	g_monster_blacklist["monster_scientist_dead"] = true;
	g_monster_blacklist["monster_sitting_scientist"] = true;
	g_monster_blacklist["monster_tripmine"] = true;
	g_monster_blacklist["monster_mortar"] = true;
	g_monster_blacklist["monster_snark"] = true;
	g_monster_blacklist["monster_babycrab"] = true;
	
	g_toggle_ents["func_button"] = true;
	g_toggle_ents["func_door"] = true;
	g_toggle_ents["func_door_rotating"] = true;
	g_toggle_ents["func_rot_button"] = true;
	g_toggle_ents["func_rotating"] = true;
	g_toggle_ents["func_train"] = true;
	g_toggle_ents["func_tracktrain"] = true;
	g_toggle_ents["func_wall_toggle"] = true;
	g_toggle_ents["momentary_rot_button"] = true;
	
	MapActivate();
	
	println("ZONE SIZE: " + ZONE_SIZE);
}

void MapActivate() {	
	g_visited_zones.resize(0);
	g_visited_zones.resize(ZONES_PER_AXIS);
	
	for (uint x = 0; x < ZONES_PER_AXIS; x++) {
		g_visited_zones[x].resize(0);
		g_visited_zones[x].resize(ZONES_PER_AXIS);
		
		for (uint y = 0; y < ZONES_PER_AXIS; y++) {
			g_visited_zones[x][y].resize(0);
			g_visited_zones[x][y].resize(ZONES_PER_AXIS);
		}
	}
	
	g_excitement = MAX_EXCITEMENT;
	g_is_boring = false;
	g_last_kinda_boring = -999;
	g_is_kinda_boring = false;
	
	reload_ents();
}

PlayerState@ getPlayerState(CBasePlayer@ plr) {
	string steamId = g_EngineFuncs.GetPlayerAuthId( plr.edict() );
	if (steamId == 'STEAM_ID_LAN') {
		steamId = plr.pev.netname;
	}
	
	if ( !g_player_states.exists(steamId) ) {
		PlayerState state;
		g_player_states[steamId] = state;
	}
	return cast<PlayerState@>( g_player_states[steamId] );
}

void update_excitement() {
	if (shouldDecreaseExcitement()) {
		g_excitement -= 0.5f;
		//g_excitement -= 5.0f;
	} else {
		g_excitement = MAX_EXCITEMENT;
	}
	
	if (g_excitement < 0) {
		g_excitement = 0;
	}
	
	for (int i = 1; i <= g_Engine.maxClients; i++) {
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		PlayerState@ state = getPlayerState(plr);
		g_excitement += state.checkExcitement(plr);
	}
	
	array<ExcitementEnt> new_ents;
	
	for (uint i = 0; i < g_excitement_ents.size(); i++) {
		ExcitementEnt@ exciteEnt = @g_excitement_ents[i]; 
		CBaseEntity@ ent = exciteEnt.h_ent;
		CBaseToggle@ toggle = cast<CBaseToggle@>(ent);
		
		if (ent is null) {
			if (exciteEnt.isKillable && exciteEnt.wasAlive) {
				int exciteAmount = int(exciteEnt.name.Find("monster_")) != -1 ? 20 : 10;
				g_excitement += exciteAmount;
				debugMessage("[AntiStall] " + exciteEnt.name + " was killed! +" + exciteAmount + " excitement\n");
			}
			continue;
		}
		
		if (isMonster(ent) and exciteEnt.wasAlive) {
			float damage = exciteEnt.lastHealth - ent.pev.health;
			
			if (!ent.IsAlive()) {
				g_excitement += 20;
				debugMessage("[AntiStall] " + exciteEnt.name + " was killed! +20 excitement\n");
			}
			else if (damage >= 50) {
				g_excitement += 10;
				debugMessage("[AntiStall] " + ent.pev.classname + " took heavy damage! +10 excitement\n");
			}
			else if (damage > 1) {
				g_excitement += 3;
				debugMessage("[AntiStall] " + ent.pev.classname + " took minor damage! +2 excitement\n");
			}	
			
			exciteEnt.lastHealth = ent.pev.health;
			exciteEnt.wasAlive = ent.IsAlive();
		}
		else if (exciteEnt.isToggleEnt and !exciteEnt.everUsed) {
			if (ent.GetToggleState() != exciteEnt.oldToggleState) {
				exciteEnt.everUsed = true;
				
				bool isReallyCool = int(string(ent.pev.classname).Find("button")) != -1;
				int neatnessLevel = isReallyCool ? 20 : 10;
				g_excitement += neatnessLevel;
				debugMessage("[AntiStall] " + ent.pev.classname + " was used for the first time! +" + neatnessLevel + " excitement\n");
			}
		}
		
		new_ents.insertLast(g_excitement_ents[i]);
	}
	
	g_excitement_ents = new_ents;
	
	if (g_excitement > MAX_EXCITEMENT) {
		g_excitement = MAX_EXCITEMENT;
	}
	
	debug_excitement();
	
	if (g_excitement < 20) {
		if (!g_is_kinda_boring) {
			bool isSpammy = g_Engine.time - g_last_kinda_boring < 60;
			//g_PlayerFuncs.ClientPrintAll(isSpammy ? HUD_PRINTNOTIFY : HUD_PRINTTALK, "[AntiStall] Warning: Excitement level is below 20.\n");
			g_PlayerFuncs.ClientPrintAll(HUD_PRINTNOTIFY, "[AntiStall] Warning: Excitement level is below 20.\n");
			g_last_kinda_boring = g_Engine.time;
		}
		g_is_kinda_boring = true;
	} else {
		g_is_kinda_boring = false;
	}
	
	if (g_excitement <= 0) {
		if (!g_is_boring) {
			g_is_boring = true;
			g_PlayerFuncs.ClientPrintAll(HUD_PRINTTALK, "[AntiStall] Excitement level is 0. Make progress or die.\n");
			g_Scheduler.SetTimeout("checkBoringRestart", 10.0f);
		}
	}
}

void doBoringRestart() {
	g_PlayerFuncs.ClientPrintAll(HUD_PRINTNOTIFY, "[AntiStall] Say \".boring\" to see how the plugin calculates excitement.\n");
	g_is_boring = false;
}

void checkBoringRestart() {	
	if (g_excitement < 10) {
		g_PlayerFuncs.ClientPrintAll(HUD_PRINTTALK, "[AntiStall] Excitement level is still below 10. Time to die.\n");
		
		for (int i = 1; i <= g_Engine.maxClients; i++) {
			CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
			
			if (plr is null or !plr.IsConnected()) {
				continue;
			}
			
			if (plr.IsAlive()) {
				g_EntityFuncs.Remove(plr);
			}
		}
		
		g_Scheduler.SetTimeout("doBoringRestart", 5.0f);
	} else {
		g_is_boring = false;
		g_PlayerFuncs.ClientPrintAll(HUD_PRINTTALK, "[AntiStall] Excitement level is at " + int(g_excitement) + ". Punishment cancelled.\n");
	}
}

void debugMessage(string msg) {
	for (int i = 1; i <= g_Engine.maxClients; i++) {
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		PlayerState@ state = getPlayerState(plr);
		
		if (state.debug) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTNOTIFY, msg);
		}
	}
}

bool areSomeDead() {
	int totalPlayers = 0;
	int totalDead = 0;
	
	for (int i = 1; i <= g_Engine.maxClients; i++) {
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		totalPlayers += 1;
		
		if (!plr.IsAlive()) {
			totalDead += 1;
		}
	}
	
	return totalPlayers > 0 and totalDead > 0 and totalDead < totalPlayers;
}

bool shouldDecreaseExcitement() {
	return g_SurvivalMode.IsActive() && areSomeDead();
}

void debug_excitement() {
	for (int i = 1; i <= g_Engine.maxClients; i++) {
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		PlayerState@ state = getPlayerState(plr);
		if (!state.debug and (!shouldDecreaseExcitement() or g_excitement > 60)) {
			continue;
		}
		
		HUDTextParams params;
		params.effect = 0;
		params.fadeinTime = 0;
		params.fadeoutTime = 0.1;
		params.holdTime = 1.0f;
		
		params.x = -1;
		params.y = 0.92;
		params.channel = 4;
		
		string info = "Excitement: " + int(g_excitement);
		
		if (!shouldDecreaseExcitement()) {
			info = "Excitement: N/A";
		}
		
		g_PlayerFuncs.HudMessage(plr, params, info);
	}	
}

bool doCommand(CBasePlayer@ plr, const CCommand@ args) {
	PlayerState@ state = getPlayerState(plr);
	
	if ( args.ArgC() > 0 ) {
		if ( args[0] == ".boring" ) {
			state.debug = !state.debug;
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[AntiStall] Debug mode " + (state.debug ? "ENABLED" : "DISABLED") + ".\n");
			return true;
		}
	}
	return false;
}

HookReturnCode ClientSay( SayParameters@ pParams ) {
	CBasePlayer@ plr = pParams.GetPlayer();
	const CCommand@ args = pParams.GetArguments();
	
	if (doCommand(plr, args)) {
		pParams.ShouldHide = true;
		return HOOK_HANDLED;
	}
	
	return HOOK_CONTINUE;
}

CClientCommand _boring("boring", "AntiStall info", @consoleCmd );

void consoleCmd( const CCommand@ args )
{
	CBasePlayer@ plr = g_ConCommandSystem.GetCurrentPlayer();
	doCommand(plr, args);
}