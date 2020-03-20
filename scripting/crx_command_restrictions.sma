#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <regex>

#tryinclude <cromchat>

#if !defined _cromchat_included
	#error "cromchat.inc" is missing in your "scripting/include" folder. Download it from: "https://amxx-bg.info/inc/"
#endif

// Comment this line to use on a mod different than Counter-Strike.
#define USE_CSTRIKE

// Uncomment to log restrictions in the server's console.
//#define CRX_CMDRESTRICTIONS_DEBUG

#if defined USE_CSTRIKE
	#include <cstrike>
#endif

#if !defined MAX_PLAYERS
	const MAX_PLAYERS = 32
#endif

#if !defined MAX_NAME_LENGTH
	const MAX_NAME_LENGTH = 32
#endif

#if !defined MAX_IP_LENGTH
	const MAX_IP_LENGTH = 16
#endif

#if !defined MAX_AUTHID_LENGTH
	const MAX_AUTHID_LENGTH = 64
#endif

const MAX_FILE_PATH_LENGTH = 256

new const PLUGIN_VERSION[]  = "1.3"
new const CMD_ARG_SAY[]     = "say"
new const CMD_ARG_SAYTEAM[] = "say_team"
new const TIME_FORMAT[]     = "%H:%M"
const MAX_COMMANDS          = 128
const MAX_CMDLINE_LENGTH    = 128
const MAX_STATUS_LENGTH     = 12
const MAX_TYPE_LENGTH       = 12
const MAX_MSG_LENGTH        = 160
const MAX_TIME_LENGTH       = 6
const MAX_INT_VALUES        = 2
const INVALID_ENTRY         = -1

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
	TYPE_LIFE,
	TYPE_TIME
}

enum _:PlayerData
{
	PDATA_NAME[MAX_NAME_LENGTH],
	PDATA_IP[MAX_IP_LENGTH],
	PDATA_STEAM[MAX_AUTHID_LENGTH]
}

enum _:RestrictionData
{
	bool:Block,
	Type,
	#if defined USE_CSTRIKE
	CsTeams:ValueTeam,
	#endif
	ValueString[MAX_AUTHID_LENGTH],
	ValueInt[MAX_INT_VALUES],
	Message[MAX_MSG_LENGTH]
}

new const g_szCommandArg[]   = "$cmd$"
new const g_szNoMessageArg[] = "#none"
new const g_szLogs[]         = "CommandRestrictions.log"
new const g_szFilename[]     = "CommandRestrictions.ini"
new const g_szTimePattern[]  = "(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})"

new Array:g_aRestrictions[MAX_COMMANDS]
new Trie:g_tCommands
new g_ePlayerData[MAX_PLAYERS + 1][PlayerData]
new g_iTotalCommands = INVALID_ENTRY
new g_iRestrictions[MAX_COMMANDS]
new g_szQueue[MAX_CMDLINE_LENGTH]
new g_fwdUserNameChanged

public plugin_init()
{
	register_plugin("Command Restrictions", PLUGIN_VERSION, "OciXCrom")
	register_cvar("CRXCommandRestrictions", PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY|FCVAR_UNLOGGED)

	register_event("SayText", "OnSayText", "a", "2=#Cstrike_Name_Change")
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
	{
		ArrayDestroy(g_aRestrictions[i])
	}

	TrieDestroy(g_tCommands)
}

public client_putinserver(id)
{
	get_user_name(id, g_ePlayerData[id][PDATA_NAME], charsmax(g_ePlayerData[][PDATA_NAME]))
	strtolower(g_ePlayerData[id][PDATA_NAME])
	get_user_ip(id, g_ePlayerData[id][PDATA_IP], charsmax(g_ePlayerData[][PDATA_IP]), 1)
	get_user_authid(id, g_ePlayerData[id][PDATA_STEAM], charsmax(g_ePlayerData[][PDATA_STEAM]))
}

public OnSayText(iMsg, iDestination, iEntity)
{
	g_fwdUserNameChanged = register_forward(FM_ClientUserInfoChanged, "OnNameChange", 1)
}

public OnNameChange(id)
{
	if(!is_user_connected(id))
	{
		return
	}

	get_user_name(id, g_ePlayerData[id][PDATA_NAME], g_ePlayerData[id][PDATA_NAME])
	strtolower(g_ePlayerData[id][PDATA_NAME])

	unregister_forward(FM_ClientUserInfoChanged, g_fwdUserNameChanged, 1)
}

ReadFile()
{
	new szConfigsName[MAX_FILE_PATH_LENGTH], szFilename[MAX_FILE_PATH_LENGTH]
	get_configsdir(szConfigsName, charsmax(szConfigsName))
	formatex(szFilename, charsmax(szFilename), "%s/%s", szConfigsName, g_szFilename)
	new iFilePointer = fopen(szFilename, "rt")

	if(iFilePointer)
	{
		new szData[MAX_CMDLINE_LENGTH + MAX_STATUS_LENGTH + MAX_TYPE_LENGTH + MAX_MSG_LENGTH], szStatus[MAX_TYPE_LENGTH], szType[MAX_STATUS_LENGTH]
		new eItem[RestrictionData], Regex:iRegex, bool:bQueue, iSize, iLine, i
		new szTemp[2][MAX_TIME_LENGTH]

		while(!feof(iFilePointer))
		{
			fgets(iFilePointer, szData, charsmax(szData))
			trim(szData)
			iLine++

			switch(szData[0])
			{
				case EOS, '#', ';': continue
				case '[':
				{
					if(bQueue && g_iTotalCommands > INVALID_ENTRY)
					{
						register_commands_in_queue()
					}

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
					else
					{
						bQueue = false
					}

					if(contain(szData, CMD_ARG_SAY) != -1)
					{
						replace(szData, charsmax(szData), CMD_ARG_SAY, "")
						trim(szData)
					}
					else
					{
						register_clcmd(szData, "OnRestrictedCommand")
					}

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
							{
								strtolower(eItem[ValueString])
							}
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
							switch(szType[1])
							{
								case 'E', 'e':
								{
									eItem[Type] = TYPE_TEAM

									if(!eItem[ValueString][0])
									{
										log_config_error(iLine, "Flag(s) not specified")
										continue
									}

									switch(eItem[ValueString][0])
									{
										case 'C', 'c': eItem[ValueTeam] = _:CS_TEAM_CT
										case 'T', 't': eItem[ValueTeam] = _:CS_TEAM_T
										case 'S', 's': eItem[ValueTeam] = _:CS_TEAM_SPECTATOR
										case 'U', 'u': eItem[ValueTeam] = _:CS_TEAM_UNASSIGNED
										default:
										{
											log_config_error(iLine, "Unknown team name ^"%s^"", eItem[ValueString])
											continue
										}
									}
								}
								case 'I', 'i':
								{
									eItem[Type] = TYPE_TIME

									if(!eItem[ValueString][0])
									{
										log_config_error(iLine, "Time not specified")
										continue
									}

									iRegex = regex_match(eItem[ValueString], g_szTimePattern, i, "", 0)

									if(_:iRegex <= 0)
									{
										log_config_error(iLine, "Wrong time format. Expected ^"Hr:Min - Hr:Min^"")
										continue
									}

									for(i = 0; i < 2; i++)
									{
										regex_substr(iRegex, i + 1, szTemp[i], charsmax(szTemp[]))
										eItem[ValueInt][i] = time_to_num(szTemp[i], charsmax(szTemp[]))

										if(eItem[ValueInt][i] < 0 || eItem[ValueInt][i] > 2359)
										{
											log_config_error(iLine, "Invalid time ^"%i^"", eItem[ValueInt][i])
											continue
										}
									}
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
								case 'A', 'a': eItem[ValueInt][0] = 1
								case 'D', 'd': eItem[ValueInt][0] = 0
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
		{
			register_commands_in_queue()
		}

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
	{
		return PLUGIN_CONTINUE
	}

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
					{
						break
					}
				}
			}
			case TYPE_IP:
			{
				if(equal(g_ePlayerData[id][PDATA_IP], eItem[ValueString]))
				{
					bBlock = eItem[Block]

					if(bBlock)
					{
						break
					}
				}
			}
			case TYPE_STEAM:
			{
				if(equal(g_ePlayerData[id][PDATA_STEAM], eItem[ValueString]))
				{
					bBlock = eItem[Block]

					if(bBlock)
					{
						break
					}
				}
			}
			case TYPE_FLAGS:
			{
				if(has_all_flags(id, eItem[ValueString]))
				{
					bBlock = eItem[Block]

					if(bBlock)
					{
						break
					}
				}
			}
			#if defined USE_CSTRIKE
			case TYPE_TEAM:
			{
				if(iTeam == eItem[ValueTeam])
				{
					bBlock = eItem[Block]

					if(bBlock)
					{
						break
					}
				}
			}
			#endif
			case TYPE_LIFE:
			{
				if(iAlive == eItem[ValueInt][0])
				{
					bBlock = eItem[Block]

					if(bBlock)
					{
						break
					}
				}
			}
			case TYPE_TIME:
			{
				CromChat(0, "checking if hrs %i - %i", eItem[ValueInt][0], eItem[ValueInt][1])
				if(is_current_time(eItem[ValueInt][0], eItem[ValueInt][1]))
				{
					CromChat(0, "yes")
					bBlock = eItem[Block]

					if(bBlock)
					{
						break
					}
				}
			}
		}
	}

	if(bBlock)
	{
		if(eItem[Message][0])
		{
			if(equal(eItem[Message], g_szNoMessageArg))
			{
				return true
			}

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

bool:is_current_time(const iStart, const iEnd)
{
	new szTime[MAX_TIME_LENGTH]
	get_time(TIME_FORMAT, szTime, charsmax(szTime))

	new iTime = time_to_num(szTime, charsmax(szTime))

	return (iStart < iEnd ? (iStart <= iTime <= iEnd) : (iStart <= iTime || iTime < iEnd))
}

time_to_num(szTime[MAX_TIME_LENGTH], iLen)
{
	replace(szTime, iLen, ":", "")
	return str_to_num(szTime)
}

register_commands_in_queue()
{
	static szData[MAX_CMDLINE_LENGTH]

	while(g_szQueue[0] != 0 && strtok(g_szQueue, szData, charsmax(szData), g_szQueue, charsmax(g_szQueue), ','))
	{
		trim(g_szQueue); trim(szData)

		if(contain(szData, CMD_ARG_SAY) != -1)
		{
			replace(szData, charsmax(szData), CMD_ARG_SAY, "")
			trim(szData)
		}
		else
		{
			register_clcmd(szData, "OnRestrictedCommand")
		}

		TrieSetCell(g_tCommands, szData, g_iTotalCommands)

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
	{
		log_to_file(g_szLogs, "%s: %s", g_szFilename, szError)
	}
	else
	{
		log_to_file(g_szLogs, "%s (%i): %s", g_szFilename, iLine, szError)
	}
}