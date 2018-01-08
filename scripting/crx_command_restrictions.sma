#include <amxmodx>
#include <amxmisc>
#include <cromchat>

//Comment this line to use on a mod different than Counter-Strike.
#define USE_CSTRIKE

//Uncomment to log restrictions in the server's console.
//#define CRX_CMDRESTRICTIONS_DEBUG

#if defined USE_CSTRIKE
	#include <cstrike>
#endif

#define PLUGIN_VERSION "1.1"
#define CMD_ARG_SAY "say"
#define CMD_ARG_SAYTEAM "say_team"
#define MAX_COMMANDS 128
#define MAX_CMDLINE_LENGTH 128
#define MAX_STATUS_LENGTH 12
#define MAX_TYPE_LENGTH 12
#define MAX_MSG_LENGTH 160
#define INVALID_ENTRY -1

enum _:Types
{
	TYPE_ALL,
	TYPE_NAME,
	TYPE_IP,
	TYPE_STEAM,
	TYPE_FLAGS,
	#if defined USE_CSTRIKE
	TYPE_TEAM,
	#endif
	TYPE_LIFE
}

enum _:PlayerData
{
	PDATA_NAME[32],
	PDATA_IP[20],
	PDATA_STEAM[35]
}

enum _:RestrictionData
{
	bool:Block,
	Type,
	#if defined USE_CSTRIKE
	CsTeams:ValueTeam,
	#endif
	ValueString[35],
	ValueInt,
	Message[MAX_MSG_LENGTH]
}

new const g_szCommandArg[] = "$cmd$"
new const g_szLogs[] = "CommandRestrictions.log"
new const g_szFilename[] = "CommandRestrictions.ini"

new Array:g_aRestrictions[MAX_COMMANDS],
	Trie:g_tCommands,
	g_ePlayerData[33][PlayerData],
	g_iTotalCommands = INVALID_ENTRY,
	g_iRestrictions[MAX_COMMANDS],
	g_szQueue[MAX_CMDLINE_LENGTH]

public plugin_init()
{
	register_plugin("Command Restrictions", PLUGIN_VERSION, "OciXCrom")
	register_cvar("CRXCommandRestrictions", PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY|FCVAR_UNLOGGED)
	register_dictionary("common.txt")
}

public plugin_precache()
{
	register_clcmd(CMD_ARG_SAY, "OnSay")
	register_clcmd(CMD_ARG_SAYTEAM, "OnSay")
	g_tCommands = TrieCreate()
	ReadFile()
}

public plugin_end()
{
	for(new i; i < g_iTotalCommands; i++)
		ArrayDestroy(g_aRestrictions[i])
		
	TrieDestroy(g_tCommands)
}

public client_putinserver(id)
{
	get_user_name(id, g_ePlayerData[id][PDATA_NAME], charsmax(g_ePlayerData[][PDATA_NAME]))
	strtolower(g_ePlayerData[id][PDATA_NAME])
	get_user_ip(id, g_ePlayerData[id][PDATA_IP], charsmax(g_ePlayerData[][PDATA_IP]), 1)
	get_user_authid(id, g_ePlayerData[id][PDATA_STEAM], charsmax(g_ePlayerData[][PDATA_STEAM]))
}

public client_infochanged(id)
{
	if(!is_user_connected(id))
		return
		
	static szNewName[32]
	get_user_info(id, "name", szNewName, charsmax(szNewName))
	
	if(!equali(szNewName, g_ePlayerData[id][PDATA_NAME]))
	{
		copy(g_ePlayerData[id][PDATA_NAME], charsmax(g_ePlayerData[][PDATA_NAME]), szNewName)
		strtolower(g_ePlayerData[id][PDATA_NAME])
	}
}

ReadFile()
{
	new szConfigsName[256], szFilename[256]
	get_configsdir(szConfigsName, charsmax(szConfigsName))
	formatex(szFilename, charsmax(szFilename), "%s/%s", szConfigsName, g_szFilename)
	new iFilePointer = fopen(szFilename, "rt")
	
	if(iFilePointer)
	{
		new szData[MAX_CMDLINE_LENGTH + MAX_STATUS_LENGTH + MAX_TYPE_LENGTH + MAX_MSG_LENGTH], szStatus[MAX_TYPE_LENGTH], szType[MAX_STATUS_LENGTH],\
		eItem[RestrictionData], bool:bQueue, iSize, iLine
		
		while(!feof(iFilePointer))
		{
			fgets(iFilePointer, szData, charsmax(szData))
			trim(szData)
			iLine++
			
			switch(szData[0])
			{
				case EOS, ';': continue
				case '[':
				{
					if(bQueue && g_iTotalCommands > INVALID_ENTRY)
						register_commands_in_queue()
						
					iSize = strlen(szData)
					
					if(szData[iSize - 1] != ']')
					{
						log_config_error(iLine, "Closing bracket not found for command ^"%s^"", szData[1])
						continue
					}
						
					szData[0] = ' '
					szData[iSize - 1] = ' '
					trim(szData)
					
					if(contain(szData, ",") != -1)
					{
						strtok(szData, szData, charsmax(szData), g_szQueue, charsmax(g_szQueue), ',')
						trim(szData); trim(g_szQueue)
						bQueue = true
					}
					else bQueue = false
					
					if(contain(szData, CMD_ARG_SAY) != -1)
					{
						replace(szData, charsmax(szData), CMD_ARG_SAY, "")
						trim(szData)
					}
					else
						register_clcmd(szData, "OnRestrictedCommand")
						
					g_aRestrictions[++g_iTotalCommands] = ArrayCreate(RestrictionData)
					TrieSetCell(g_tCommands, szData, g_iTotalCommands)
					
					#if defined CRX_CMDRESTRICTIONS_DEBUG
					log_config_error(_, "RN #%i: %s", g_iTotalCommands, szData)
					#endif
				}
				default:
				{
					eItem[ValueString][0] = EOS
					eItem[Message][0] = EOS
					parse(szData, szStatus, charsmax(szStatus), szType, charsmax(szType), eItem[ValueString], charsmax(eItem[ValueString]), eItem[Message], charsmax(eItem[Message]))
					
					switch(szStatus[0])
					{
						case 'A', 'a': eItem[Block] = false
						case 'B', 'b': eItem[Block] = true
						default:
						{
							log_config_error(iLine, "Unknown status type ^"%s^"", szStatus)
							continue
						}
					}
					
					switch(szType[0])
					{
						case 'A', 'a': eItem[Type] = TYPE_ALL
						case 'N', 'n':
						{
							eItem[Type] = TYPE_NAME
							
							if(!eItem[ValueString][0])
							{
								log_config_error(iLine, "Name not specified")
								continue
							}
							else
								strtolower(eItem[ValueString])
						}
						case 'I', 'i':
						{
							eItem[Type] = TYPE_IP
							
							if(!eItem[ValueString][0])
							{
								log_config_error(iLine, "IP address not specified")
								continue
							}
						}
						case 'S', 's':
						{
							eItem[Type] = TYPE_STEAM
							
							if(!eItem[ValueString][0])
							{
								log_config_error(iLine, "SteamID not specified")
								continue
							}
						}
						case 'F', 'f':
						{
							eItem[Type] = TYPE_FLAGS
							
							if(!eItem[ValueString][0])
							{
								log_config_error(iLine, "Flag(s) not specified")
								continue
							}
						}
						#if defined USE_CSTRIKE
						case 'T', 't':
						{
							eItem[Type] = TYPE_TEAM
							
							if(!eItem[ValueString][0])
							{
								log_config_error(iLine, "Flag(s) not specified")
								continue
							}
							
							switch(eItem[ValueString][0])
							{
								case 'C', 'c': eItem[ValueTeam] = CS_TEAM_CT
								case 'T', 't': eItem[ValueTeam] = CS_TEAM_T
								case 'S', 's': eItem[ValueTeam] = CS_TEAM_SPECTATOR
								case 'U', 'u': eItem[ValueTeam] = CS_TEAM_UNASSIGNED
								default:
								{
									log_config_error(iLine, "Unknown team name ^"%s^"", eItem[ValueString])
									continue
								}
							}
						}
						#endif
						case 'L', 'l':
						{
							eItem[Type] = TYPE_LIFE
							
							if(!eItem[ValueString][0])
							{
								log_config_error(iLine, "Life status not specified")
								continue
							}
							
							switch(eItem[ValueString][0])
							{
								case 'A', 'a': eItem[ValueInt] = 1
								case 'D', 'd': eItem[ValueInt] = 0
								default:
								{
									log_config_error(iLine, "Unknown life status ^"%s^"", eItem[ValueString])
									continue
								}
							}
						}
						default:
						{
							log_config_error(iLine, "Unknown information type ^"%s^"", szType)
							continue
						}
					}
						
					g_iRestrictions[g_iTotalCommands]++
					ArrayPushArray(g_aRestrictions[g_iTotalCommands], eItem)
				}
			}
		}
		
		fclose(iFilePointer)
		
		if(bQueue)
			register_commands_in_queue()
		
		if(g_iTotalCommands == INVALID_ENTRY)
		{
			log_config_error(_, "No command restrictions found.")
			pause("ad")
		}
	}
	else
	{
		log_config_error(_, "Configuration file not found or cannot be opened.")
		pause("ad")
	}
}

public OnSay(id)
{
	new szArg[32], szCommand[32]
	read_argv(1, szArg, charsmax(szArg))
	parse(szArg, szCommand, charsmax(szCommand), szArg, charsmax(szArg))
	
	if(!TrieKeyExists(g_tCommands, szCommand))
		return PLUGIN_CONTINUE
		
	return is_restricted(id, szCommand) ? PLUGIN_HANDLED : PLUGIN_CONTINUE
}

public OnRestrictedCommand(id)
{
	new szCommand[32]
	read_argv(0, szCommand, charsmax(szCommand))		
	return is_restricted(id, szCommand) ? PLUGIN_HANDLED : PLUGIN_CONTINUE
}

bool:is_restricted(const id, const szCommand[])
{
	static eItem[RestrictionData], bool:bBlock, iCommand, iAlive, i
	TrieGetCell(g_tCommands, szCommand, iCommand)
	bBlock = false
	
	#if defined USE_CSTRIKE
	static CsTeams:iTeam
	#endif
	
	iAlive = is_user_alive(id)
	iTeam = cs_get_user_team(id)
	
	for(i = 0; i < g_iRestrictions[iCommand]; i++)
	{
		ArrayGetArray(g_aRestrictions[iCommand], i, eItem)
		
		switch(eItem[Type])
		{
			case TYPE_ALL: bBlock = eItem[Block]
			case TYPE_NAME:
			{
				if(equal(g_ePlayerData[id][PDATA_NAME], eItem[ValueString]))
				{
					bBlock = eItem[Block]
					
					if(bBlock)
						break
				}
			}
			case TYPE_IP:
			{
				if(equal(g_ePlayerData[id][PDATA_IP], eItem[ValueString]))
				{
					bBlock = eItem[Block]
					
					if(bBlock)
						break
				}
			}
			case TYPE_STEAM:
			{
				if(equal(g_ePlayerData[id][PDATA_STEAM], eItem[ValueString]))
				{
					bBlock = eItem[Block]
					
					if(bBlock)
						break
				}
			}
			case TYPE_FLAGS:
			{
				if(has_all_flags(id, eItem[ValueString]))
				{
					bBlock = eItem[Block]
					
					if(bBlock)
						break
				}
			}
			#if defined USE_CSTRIKE
			case TYPE_TEAM:
			{
				if(iTeam == eItem[ValueTeam])
				{
					bBlock = eItem[Block]
					
					if(bBlock)
						break
				}
			}
			#endif
			case TYPE_LIFE:
			{
				if(iAlive == eItem[ValueInt])
				{
					bBlock = eItem[Block]
					
					if(bBlock)
						break
				}
			}
		}
	}
	
	if(bBlock)
	{
		if(eItem[Message][0])
		{
			static szMessage[MAX_MSG_LENGTH]
			copy(szMessage, charsmax(szMessage), eItem[Message])
			replace_all(szMessage, charsmax(szMessage), g_szCommandArg, szCommand)
			client_print(id, print_console, szMessage)
			CC_SendMessage(id, szMessage)
		}
		else
		{
			client_print(id, print_console, "%L (%s)", id, "NO_ACC_COM", szCommand)
			CC_SendMessage(id, "&x07%L &x01(&x04%s&x01)", id, "NO_ACC_COM", szCommand)
		}
		
		return true
	}
	
	return false
}

register_commands_in_queue()
{
	static szData[MAX_CMDLINE_LENGTH], iPrevious
	
	while(g_szQueue[0] != 0 && strtok(g_szQueue, szData, charsmax(szData), g_szQueue, charsmax(g_szQueue), ','))
	{
		iPrevious = g_iTotalCommands
		trim(g_szQueue); trim(szData)
		register_clcmd(szData, "OnRestrictedCommand")
		g_aRestrictions[++g_iTotalCommands] = ArrayClone(g_aRestrictions[iPrevious])
		TrieSetCell(g_tCommands, szData, g_iTotalCommands)
		g_iRestrictions[g_iTotalCommands] = g_iRestrictions[iPrevious]
		
		#if defined CRX_CMDRESTRICTIONS_DEBUG
		log_config_error(_, "RQ #%i: %s", g_iTotalCommands, szData)
		#endif
	}

	g_szQueue[0] = EOS
}

log_config_error(const iLine = INVALID_ENTRY, const szInput[], any:...)
{
	new szError[128]
	vformat(szError, charsmax(szError), szInput, 3)
	
	if(iLine == INVALID_ENTRY)
		log_to_file(g_szLogs, "%s: %s", g_szFilename, szError)
	else
		log_to_file(g_szLogs, "%s (%i): %s", g_szFilename, iLine, szError)
}