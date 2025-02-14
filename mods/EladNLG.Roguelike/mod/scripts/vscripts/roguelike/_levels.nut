untyped
global function Levels_Init
global function AddXP
global function GetLevel
global function CalculateXPForLevel

const int BASE_XP_PER_LEVEL = 250
const float XP_PER_LEVEL_MULTIPLIER = 1.1

int xp = 0
int level = 0

bool xpot = false

bool function OnXpot( entity player, array<string> args )
{
    if (!GetConVarBool("sv_cheats"))
        return false
    xpot = !xpot
    return true
}

bool function OnTele( entity player, array<string> args )
{
    if (!GetConVarBool("sv_cheats"))
        return false
    
    try
    {
        vector pos = <float(args[0]), float(args[1]), float(args[2])>
        vector ang = <float(args[3]), float(args[4]), float(args[5])>
        vector vel = <float(args[6]), float(args[7]), float(args[8])>

        player.SetOrigin(pos)
        player.SetAngles(ang)
        player.SetVelocity(vel)
    }
    catch (ex)
    {
        
    }
    return true
}

void function Levels_Init()
{
    xp = GetConVarInt( "player_xp" )
    level = GetConVarInt( "player_level" )
    print("\nXP: " + xp + "\nLEVEL: " + level)

    #if SP
    AddCallback_OnLevelEnd( OnLevelEnd )
    AddCallback_OnLoadSaveGame( OnLoadSaveGame )
    #endif
    AddClientCommandCallback( "xpot", OnXpot )
    AddClientCommandCallback( "tele", OnTele )
    AddCallback_OnPlayerRespawned( ClientConnected )
    thread Levels_Update()
}

void function OnLoadSaveGame( entity player )
{
    SetConVarInt( "level_count", levelCount )
    Roguelike_RollItemsInShop()
    thread UpdateLevels()
}

void function UpdateLevels()
{
    WaitFrame()

    foreach ( entity player in GetPlayerArray() )
    {
        Remote_CallFunction_NonReplay( player, "ServerCallback_SetXP", xp, level, XP_PER_LEVEL_MULTIPLIER, BASE_XP_PER_LEVEL )
    }
}

void function Levels_Update()
{
    while( true )
    {
        foreach (entity player in GetPlayerArray())
            if (IsAlive( player ) && player.GetMaxHealth() != CalculatePlayerMaxHP( player ))
            {
                Remote_CallFunction_Replay( player, "ServerCallback_SetXP", xp, level, XP_PER_LEVEL_MULTIPLIER, BASE_XP_PER_LEVEL )
                OnLevelUp()
            }
        if (xpot) AddXP( 30 )
        WaitFrame()
    }
}
void function ClientConnected( entity player )
{
    Remote_CallFunction_Replay( player, "ServerCallback_SetXP", xp, level, XP_PER_LEVEL_MULTIPLIER, BASE_XP_PER_LEVEL )
    
    int startPointMax = 0
    switch (GetMapName())
    {
        case "sp_s2s":
            startPointMax = 7
            break
        case "sp_hub_timeshift":
            startPointMax = 3
            break
    } 
    if (Roguelike_GetStartPoint() < startPointMax)
    {
        print("\n\nhello there.\nSTART POINT: " + Roguelike_GetStartPoint())
        Remote_CallFunction_NonReplay( player, "ServerCallback_HideTimer" )
    }

    OnLevelUp()
}

int function CalculateXPForLevel( int level )
{
    return int(BASE_XP_PER_LEVEL * /*pow( XP_PER_LEVEL_MULTIPLIER, level )*/ (1.0 + (level * (XP_PER_LEVEL_MULTIPLIER - 1.0))))
}

int function GetLevel()
{
    return level
}

void function AddXP( int amount )
{
    xp += amount
    while ( xp >= CalculateXPForLevel( level ) )
    {
        level += 1
        xp -= CalculateXPForLevel( level - 1 )
    }
    while ( xp < 0 )
    {
        level -= 1
        xp += CalculateXPForLevel( level )
    }

    foreach (player in GetPlayerArray())
    {
        Remote_CallFunction_Replay( player, "ServerCallback_SetXP", xp, level, XP_PER_LEVEL_MULTIPLIER, BASE_XP_PER_LEVEL )
    }
}

int function CalculatePlayerMaxHP( entity player )
{
    int baseHP = int(player.GetPlayerModHealth())

    baseHP = int(RoundToNearestInt(baseHP * (1.0 - Roguelike_GetItemCount( player, "fatigue" ) * 0.2)))
    baseHP = int(RoundToNearestInt(baseHP * (1.0 + Roguelike_GetItemCount( player, "max_hp" ) * 0.1)))

    if (player.IsTitan())
    {
        if (IsValid(player.GetTitanSoul()) && player.GetTitanSoul().IsDoomed())
            baseHP /= 5
    }

    return maxint(1, int(baseHP + 0.3 * baseHP * level))
}

int function CalculatePlayerMaxShield( entity player )
{
    int baseHP = 1000

    baseHP = int(RoundToNearestInt(baseHP * (1.0 - Roguelike_GetItemCount( player, "fatigue" ) * 0.2)))
    baseHP = int(RoundToNearestInt(baseHP * (1.0 + Roguelike_GetItemCount( player, "shield" ) * CalculatePlayerMaxHP( player ) * 0.1)))

    /*if (player.IsTitan())
    {
        if (player.GetTitanSoul().IsDoomed())
            baseHP /= 5
    }*/

    return maxint(1, baseHP)
}

void function OnLevelUp()
{
    foreach (entity player in GetPlayerArray())
    {
        if (!IsAlive( player )) continue
        int baseHP = CalculatePlayerMaxHP(player)
        
        float healthFrac = float(player.GetHealth()) / player.GetMaxHealth()
        if (baseHP > 524287)
            player.s.divisor <- float(baseHP) / 524287
        baseHP = int(min(baseHP, 524287))
        player.SetMaxHealth(baseHP)
        player.SetHealth( int(min(baseHP, baseHP * healthFrac)) )
        
        float shieldFrac = float(player.GetShieldHealth()) / player.GetShieldHealthMax()
        int baseShield = CalculatePlayerMaxShield( player )
        baseShield = int(min(baseShield, 524287))
        player.SetShieldHealthMax(baseShield)
        player.SetShieldHealth( int(min(baseShield, baseShield * shieldFrac)) )
    }
}

void function OnLevelEnd( string mapName, LevelTransitionStruct trans )
{
    SetConVarInt( "player_xp", xp )
    SetConVarInt( "player_level", level )
    SetConVarInt( "roguelike_seed", GetRoguelikeSeed() + xorshift32(GetRoguelikeSeed() + 2))
}