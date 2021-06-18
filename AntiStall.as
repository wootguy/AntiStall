void print(string text) { g_Game.AlertMessage( at_console, text); }
void println(string text) { print(text + "\n"); }

const float STALL_CHECK_INTERVAL = 1.0f;

dictionary g_player_states;
dictionary g_monster_blacklist; // boring monsters that can't possibly be exciting

array<array<array<uint32>>> g_visited_zones;
array<ExcitementEnt> g_excitement_ents;

const int ZONES_PER_AXIS = 128;
const Vector MIN_ZONE_COORDS = Vector(-16384, -16384, -16384);
const float ZONE_SIZE = abs(MIN_ZONE_COORDS.x*2) / ZONES_PER_AXIS;

float g_last_progress; // last time any progress was made (new area discovered or enemy damaged)
float g_excitement; // how interesting the game is to watch (0-100)

class ExcitementEnt {
	EHandle h_ent;
	float lastHealth;
	bool everUsed = false;
	
	ExcitementEnt(EHandle h_ent) {
		this.h_ent = h_ent;
	}
}

class Color
{ 
	uint8 r, g, b, a;
	Color() { r = g = b = a = 0; }
	Color(uint8 r, uint8 g, uint8 b) { this.r = r; this.g = g; this.b = b; this.a = 255; }
	Color(uint8 r, uint8 g, uint8 b, uint8 a) { this.r = r; this.g = g; this.b = b; this.a = a; }
	Color(float r, float g, float b, float a) { this.r = uint8(r); this.g = uint8(g); this.b = uint8(b); this.a = uint8(a); }
	Color (Vector v) { this.r = uint8(v.x); this.g = uint8(v.y); this.b = uint8(v.z); this.a = 255; }
	string ToString() { return "" + r + " " + g + " " + b + " " + a; }
	Vector getRGB() { return Vector(r, g, b); }
}

Color RED    = Color(255,0,0);
Color GREEN  = Color(0,255,0);
Color BLUE   = Color(0,0,255);
Color YELLOW = Color(255,255,0);
Color ORANGE = Color(255,127,0);
Color PURPLE = Color(127,0,255);
Color PINK   = Color(255,0,127);
Color TEAL   = Color(0,255,255);
Color WHITE  = Color(255,255,255);
Color BLACK  = Color(0,0,0);
Color GRAY  = Color(127,127,127);

void te_beampoints(Vector start, Vector end, string sprite="sprites/laserbeam.spr", uint8 frameStart=0, uint8 frameRate=100, uint8 life=20, uint8 width=2, uint8 noise=0, Color c=GREEN, uint8 scroll=32, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) { NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);m.WriteByte(TE_BEAMPOINTS);m.WriteCoord(start.x);m.WriteCoord(start.y);m.WriteCoord(start.z);m.WriteCoord(end.x);m.WriteCoord(end.y);m.WriteCoord(end.z);m.WriteShort(g_EngineFuncs.ModelIndex(sprite));m.WriteByte(frameStart);m.WriteByte(frameRate);m.WriteByte(life);m.WriteByte(width);m.WriteByte(noise);m.WriteByte(c.r);m.WriteByte(c.g);m.WriteByte(c.b);m.WriteByte(c.a);m.WriteByte(scroll);m.End(); }

void add_excitement_ent(CBaseEntity@ ent) {
	if (ent.IsMonster() && string(ent.pev.classname).Find("monster_") == 0) {
		if (g_monster_blacklist.exists(ent.pev.classname)) {
			return;
		}
		g_excitement_ents.insertLast(ExcitementEnt(EHandle(ent)));
	} else if (ent.IsBreakable()) {
		g_excitement_ents.insertLast(ExcitementEnt(EHandle(ent)));
	}
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

class PlayerState {
	array<Vector> lastPositions; // everywhere this player has been, since X time ago

	PlayerState() {}
	
	void addPosition(Vector pos) {
		lastPositions.insertLast(pos);
		
		int maxHistory = int(g_stallMoveTime.GetFloat() / STALL_CHECK_INTERVAL);
		
		while (int(lastPositions.size()) > maxHistory) {
			lastPositions.removeAt(0);
		}
		
		println("HISTORY " + lastPositions.size() + " / " + maxHistory);
	}
	
	bool isStalling(CBasePlayer@ plr) {
		Vector mins = Vector(9e9, 9e9, 9e9);
		Vector maxs = Vector(-9e9, -9e9, -9e9);
		
		for (uint i = 0; i < lastPositions.size(); i++) {
			Vector p = lastPositions[i];
			
			maxs = Vector(Math.max(p.x, maxs.x), Math.max(p.y, maxs.y), Math.max(p.z, maxs.z));
			mins = Vector(Math.min(p.x, mins.x), Math.min(p.y, mins.y), Math.min(p.z, mins.z));
		}
		
		float size = (maxs - mins).Length();
		
		println("AREA SIZE: " + size);
		
		drawBox(mins, maxs);
		
		if (size < 512) {
			//return true; // so small of an area that player is probably just running in circles
		}
		if (size < 1024) {
			
		}
		
		Vector zoneCoords = plr.pev.origin - MIN_ZONE_COORDS;
		
		int zoneX = int(zoneCoords.x / ZONE_SIZE);
		int zoneY = int(zoneCoords.y / ZONE_SIZE);
		int zoneZ = int(zoneCoords.z / ZONE_SIZE);
		
		if (zoneX < 0 or zoneX >= ZONES_PER_AXIS or zoneY < 0 or zoneY >= ZONES_PER_AXIS or zoneZ < 0 or zoneZ >= ZONES_PER_AXIS) {
			println("ZONE OUT OF BOUNDS");
		} else {
			bool isNew = false;
			
			if (g_visited_zones[zoneX][zoneY][zoneZ] & getPlayerBit(plr) == 0) {
				g_visited_zones[zoneX][zoneY][zoneZ] |= getPlayerBit(plr);
				isNew = true;
				g_last_progress = g_EngineFuncs.Time();
				g_PlayerFuncs.ClientPrintAll(HUD_PRINTNOTIFY, "[AntiStall] " + plr.pev.netname + " found a new area! +10 excitement\n");
				g_excitement = Math.min(g_excitement + 10, 100);
				println("ZONE " + zoneX + " " + zoneY + " " + zoneZ + " (NEW!)");
			} else {
				println("ZONE " + zoneX + " " + zoneY + " " + zoneZ);
			}
			
			
		}
		
		return false;
	}
}

uint32 getPlayerBit(CBaseEntity@ plr) {
	return (1 << (plr.entindex() & 31));
}

void drawBox(Vector mins, Vector maxs) {
	Color color = YELLOW;
		
	Vector v1 = Vector(mins.x, mins.y, mins.z);
	Vector v2 = Vector(maxs.x, mins.y, mins.z);
	Vector v3 = Vector(maxs.x, maxs.y, mins.z);
	Vector v4 = Vector(mins.x, maxs.y, mins.z);
	
	Vector v5 = Vector(mins.x, mins.y, maxs.z);
	Vector v6 = Vector(maxs.x, mins.y, maxs.z);
	Vector v7 = Vector(maxs.x, maxs.y, maxs.z);
	Vector v8 = Vector(mins.x, maxs.y, maxs.z);
	
	te_beampoints(v1, v2, "sprites/laserbeam.spr", 0, 0, 10, 2, 0, color, 32, MSG_BROADCAST);
	te_beampoints(v2, v3, "sprites/laserbeam.spr", 0, 0, 10, 2, 0, color, 32, MSG_BROADCAST);
	te_beampoints(v3, v4, "sprites/laserbeam.spr", 0, 0, 10, 2, 0, color, 32, MSG_BROADCAST);
	te_beampoints(v4, v1, "sprites/laserbeam.spr", 0, 0, 10, 2, 0, color, 32, MSG_BROADCAST);
	
	te_beampoints(v5, v6, "sprites/laserbeam.spr", 0, 0, 10, 2, 0, color, 32, MSG_BROADCAST);
	te_beampoints(v6, v7, "sprites/laserbeam.spr", 0, 0, 10, 2, 0, color, 32, MSG_BROADCAST);
	te_beampoints(v7, v8, "sprites/laserbeam.spr", 0, 0, 10, 2, 0, color, 32, MSG_BROADCAST);
	te_beampoints(v8, v5, "sprites/laserbeam.spr", 0, 0, 10, 2, 0, color, 32, MSG_BROADCAST);
	
	te_beampoints(v1, v5, "sprites/laserbeam.spr", 0, 0, 10, 2, 0, color, 32, MSG_BROADCAST);
	te_beampoints(v2, v6, "sprites/laserbeam.spr", 0, 0, 10, 2, 0, color, 32, MSG_BROADCAST);
	te_beampoints(v3, v7, "sprites/laserbeam.spr", 0, 0, 10, 2, 0, color, 32, MSG_BROADCAST);
	te_beampoints(v4, v8, "sprites/laserbeam.spr", 0, 0, 10, 2, 0, color, 32, MSG_BROADCAST);
}

void PluginInit() {
	g_Module.ScriptInfo.SetAuthor( "w00tguy" );
	g_Module.ScriptInfo.SetContactInfo( "https://github.com/wootguy" );
	
	g_Scheduler.SetInterval("update_excitement", STALL_CHECK_INTERVAL, -1);
	
	MapActivate();
	
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
	
	println("ZONE SIZE: " + ZONE_SIZE);
}

void MapActivate() {
	g_player_states.clear();
	
	g_last_progress = 0;
	
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
	
	g_excitement = 100;
	
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
	g_excitement -= 1.0f;
	
	if (g_excitement < 0) {
		g_excitement = 0;
	}
	
	// TODO: revives + buttons + doors + monster damage
	
	for (int i = 1; i <= g_Engine.maxClients; i++) {
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		PlayerState@ state = getPlayerState(plr);
		
		if (plr.IsAlive()) {
			state.addPosition(plr.pev.origin);
			if (state.isStalling(plr)) {
				//println("UH OH");
			}
		} else {
			state.lastPositions.resize(0);
		}
		
		HUDTextParams params;
		params.effect = 0;
		params.fadeinTime = 0;
		params.fadeoutTime = 0.1;
		params.holdTime = 1.5f;
		
		params.x = -1;
		params.y = 0.99;
		params.channel = 2;
		
		string info = "Excitement: " + int(g_excitement) + "%";
		
		g_PlayerFuncs.HudMessage(plr, params, info);
	}
	
	array<EHandle> new_ents;
	
	for (uint i = 0; i < g_excitement_ents.size(); i++) {
		CBaseEntity@ ent = g_excitement_ents[i];
		if (ent is null) {
			continue;
		}
		
		if (ent.IsMonster()) {
		
		}
		
		new_ents.insertLast(g_excitement_ents[i]);
	}
	
	g_excitement_ents = new_ents;
}
