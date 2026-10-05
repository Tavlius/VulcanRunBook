std = "lua51"
max_line_length = 120
self = false
unused_args = false
-- Globals the addon defines
globals = {
  "VulcanRunBookDB", "VulcanRunBookCharDB", "SlashCmdList", "SLASH_VULCANRUNBOOK1", "SLASH_VULCANRUNBOOK2", "SLASH_VULCANRUNBOOK3",
  "BINDING_HEADER_VULCANRUNBOOK", "BINDING_NAME_VULCANRUNBOOK_TOGGLE", "BINDING_NAME_VULCANRUNBOOK_HISTORY",
  "VulcanRunBook_ToggleLive", "VulcanRunBook_ToggleHistory", "VulcanRunBook_OnAddonCompartmentClick", "VulcanRunBook_MarkBoss",
  "BINDING_NAME_VULCANRUNBOOK_BOSS",
}
-- WoW client API the addon reads
read_globals = { "UIErrorsFrame", "ReloadUI", "C_AddOns", "GetAddOnMetadata",
  "issecretvalue", "C_DateAndTime", "C_BattleNet", "C_FriendList", "UnitGUID", "C_Item", "C_ChatInfo", "C_Timer", "GetItemInfo", "SendChatMessage", "SendAddonMessage",
  "RegisterAddonMessagePrefix", "GetServerTime", "GetTime", "time", "date", "CreateFrame", "UnitName",
  "Ambiguate", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_MULTIPLE", "LOOT_ITEM",
  "INSTANCE_RESET_SUCCESS", "TRANSFER_ABORT_TOO_MANY_INSTANCES", "ERR_TOO_MANY_INSTANCES", "IsInInstance",
  "GetInstanceInfo", "UnitIsDeadOrGhost", "UnitIsFeignDeath", "GetNumGroupMembers", "GetNormalizedRealmName", "UnitInRaid", "IsInRaid", "IsInGroup",
  "Auctionator", "GetMoney", "UnitXP", "UnitXPMax", "Enum", "wipe", "UIParent", "BackdropTemplateMixin",
  "UISpecialFrames", "ChatFontNormal", "GetBuildInfo", "C_Map", "C_Container", "NUM_TOTAL_EQUIPPED_BAG_SLOTS",
  "NUM_BAG_SLOTS", "GetInventoryItemID", "GetInventoryItemCount", "UnitIsUnit", "UnitIsConnected",
  "LE_PARTY_CATEGORY_INSTANCE", "LE_PARTY_CATEGORY_HOME", "UNKNOWNOBJECT",
}
