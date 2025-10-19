--!strict
--!native
local pulse = {Helper = {}};

--local get_service;
local game, pcall, unpack, task, warn, error, type, typeof, tostring, clone = game, pcall, unpack, task, warn, error, type, typeof, tostring, table.clone;


local data_store = game:GetService("DataStoreService");
local Core = data_store:GetDataStore("aauag");

local http_service = game:GetService("HttpService");
local new_data: {[string]: mock_group} = {};


local group_service = game:GetService("GroupService");
local pulse_config = require("@self/Config");

local max_retries: number = pulse_config.max_retries;
local yield_time: number = pulse_config.yield_time;

local players = game:GetService("Players");
local run_service = game:GetService("RunService");

local is_studio: boolean = run_service:IsStudio();
local permissions = pulse_config.Permissions;

local log = @native function(...: any): ()
	warn("[Pulse Print]", ...);
	return;
end;


local assert = @native function(conditional: any, message: string?): ()
	if (not conditional) then
		warn("[Pulse Expection]", message or "Assert Failure", debug.traceback("", 3));
		return coroutine.yield(coroutine.running());
		--error(message or "Assert Failure", 2);
	end;
	return;	
end;
local Handler = @native function(Method: string, ...: any): any
	local arugments: {[number]: any} = {...};
	local count: number = 0;
	
	local succ: boolean, data: any = pcall(@native function(): any?
		return Core[Method](Core, unpack(arugments));
	end);
	while (not succ) do
		if (count >= max_retries) then
			log(`[Pulse Critcal] Datastore method {Method} has failed after {count} tries, aborting.`);
			break;
		end;
		
		log(`Datastore failure when calling method {Method} because of {data}`);
		succ, data = pcall(@native function(): any
			return Core[Method](Core, unpack(arugments));
		end);
		
		task.wait(yield_time);
		count += 1;
	end;
	
	if (type(data) == "string") then return nil; end;
	return data;
end;

local GetGroupInfoAsync = @native function(group_id: number): group_info_async_result
	local count: number = 0;
	local succ: boolean, group_information: group_info_async_result = pcall(group_service.GetGroupInfoAsync, group_service, group_id);
	while (not succ) do
		if (count >= max_retries) then
			log(`[Pulse Critcal] GetGroupInfoAsync failed after {count} tries, aborting any new attempts.`);
			break;
		end;
		succ, group_information = pcall(group_service.GetGroupInfoAsync, group_service, group_id);

		log(`GetGroupInfoAsync failure, {group_information} retrying.`);
		count += 1;

		task.wait(yield_time);
	end;
	return group_information;
end;
type group_member = {
	user_id: number;
	role_name: string;	
	user_name: string?; -- This will be automatically written.
	role_index: number? -- This will be automatically written.
};

export type mock_list = {
	group_id: number;
	Owner: number;
	Members: {[number]: group_member};
};
export type group_info_async_result = {
	EmblemUrl: string;
	Id: number;
	Name: string;
	Owner: {
		Id: number;
		Name: string;
	};
	Description: string;
	Roles: {[number]: {Name: string, Rank: number}};
};

export type mock_group = {
	Owner: number;
	GroupInfoAsyncResult: group_info_async_result;
	Id: number;
	Members: {[string]: group_member};
};
@native function pulse.Helper.GetRoleInfo(group_id: number, role_name: string): (number, {Name: string, Rank: number})
	assert(group_id and type(group_id) == "number", `Expected number for group_id when calling GetRoleIndex, got {typeof{group_id}}`);
	assert(group_id and type(role_name) == "string", `Expected string for role_name when calling GetRoleIndex, got {typeof{role_name}}`);

	local group_info: group_info_async_result = GetGroupInfoAsync(group_id);
	local result: number, role: any = 0, {};

	for i: number, v in (group_info.Roles) do
		if (v.Name == role_name) then
			result, role = i, v;
			break;
		end;
	end;
	
	assert(result ~= 0, `GetRoleInfo failure.`);
	return result, role;
end;

@native function pulse.Helper:GetRegisteredGroups()
	return clone(new_data);
end;
local has_permission = @native function(user_id: number, action: string): boolean
	if (action == "ALL") then
		return (permissions.ALL[user_id] ~= nil)
	elseif (action == "GROUP") then
		return (permissions.GROUP[user_id] ~= nil);	
	elseif (action == "PERMISSION") then
		return (permissions.GROUP[user_id] ~= nil or permissions.ALL[user_id] ~= nil);	
	end;
	return false;
end;


@native function pulse:KickUserAsync(group_id: number, user_id: number, caller: Player?): ()
	assert(user_id and type(user_id) == "number", `KickUserAsync expects a number for user_id but got {typeof(user_id)}`);
	assert(is_studio or caller ~= nil or typeof(caller) == "Instance" or not caller:IsA("Player"), "The caller parameter is required.");
	
	assert(group_id and type(group_id) == "number", `KickUserAsync expects a number for group_id but got {typeof(group_id)}`);
	local group = new_data[tostring(group_id)];
	
	assert(group, `Group ID {group_id} isn't registered by Pulse.`);
	assert(group.Owner ~= user_id, `Cannot kick Group Owner.`);
	
	local member = group.Members[tostring(user_id)];
	assert(member, `User ID {user_id} is not a valid member of group {group.GroupInfoAsyncResult.Name}`);
	
	if (caller) then
		local caller_member = group.Members[tostring(caller.UserId)];
		if (not caller_member or caller_member.role_index >= member.role_index or caller.UserId == user_id and caller.UserId ~= game.CreatorId) then
			log(`Illegal kick attempt from {caller}`);
			return;
		end;
	end;
	
	group.Members[tostring(user_id)] = nil :: never;
	log(`{member.user_name} has been kicked from group {group.GroupInfoAsyncResult.Name} by {is_studio and "STUDIO" or tostring(caller)}`);
	
	return;
end;
@native function pulse.MockGroup(group_list: {[any]:  mock_list}): ()
	assert(group_list and type(group_list) == "table", `[Pulse Critical] Expected group_list to be a table when calling .MockGroup, but got {typeof(group_list)}.`);
	local count: number = 0;
	
	for _: unknown, v: mock_list in (group_list) do
		if (not v.group_id or type(v.group_id) ~= "number" or new_data[tostring(v.group_id)]) then
			continue;
		end;
		local group_information = GetGroupInfoAsync(v.group_id);
		
		if (not group_information) then continue; end;
		if (not v.Owner or type(v.Owner) ~= "number") then
			v.Owner = game.CreatorId;
		end;
		
		for i: any, data: any in (v.Members) do
			local new_data = data;
			table.remove(v.Members, i);
			
			new_data.role_index = pulse.Helper.GetRoleInfo(v.group_id, data.role_name) :: number;
			new_data.user_name = players:GetNameFromUserIdAsync(data.user_id) :: string;
			
			assert(type(new_data.role_index) == "number", `[Pulse Critcal] Role name {data.role_name} is not a valid role of group {group_information.Name}`);
			local user_id: any = tostring(data.user_id);
			
			v.Members[user_id] = new_data;
			log("Ranked", new_data.user_name, "in group", group_information.Name, "to rank", data.role_name);
		end;
		
		new_data[tostring(group_information.Id)] = {
			Owner = v.Owner;
			Members = v.Members;
			Id = group_information.Id;
			GroupInfoAsyncResult = group_information;
		} :: any;
	end;
	
	return;
end;

@native function pulse:JoinGroupAsync(user_id: number, group_id: number, rank: string, caller: Player?): ()
	assert(user_id and type(user_id) == "number", `JoinGroupAsync expects a number for user_id but got {typeof(user_id)}`);
	assert(group_id and type(group_id) == "number", `JoinGroupAsync expects a number for group_id but got {typeof(group_id)}`);
	
	assert(rank and type(rank) == "string", `JoinGroupAsync expects a rank for rank but got {typeof(rank)}`);
	assert(is_studio or caller ~= nil or typeof(caller) == "Instance" or not caller:IsA("Player"), "The caller parameter is required.");
	
	assert(user_id ~= game.CreatorId, "You cannot perform actions on Game Creator.");
	assert(new_data[tostring(group_id)], `JoinGroupAsync failed because provided group id {group_id} isn't registered by Pulse.`);
	
	assert(new_data[tostring(group_id)].Members[tostring(user_id)] == nil, `{user_id} is already a member of group {group_id}, use RankUserAsync if you wish to change the user's rank.`);
	local group = new_data[tostring(group_id)];
	
	if (caller) then
		local caller_member_data: group_member = group.Members[tostring(caller.UserId)];
		if (not caller_member_data or not has_permission(caller.UserId, "ALL")) then
			log(`Unauthroized group join attempt from {caller} to {user_id}`);
			return;
		end;
		if (not is_studio and caller.UserId == user_id and game.CreatorId ~= user_id) then
			log(`Illegal JoinGroupAsync attempt.`);
			return;
		end;
	end;
	
	local index, info = pulse.Helper.GetRoleInfo(group_id, rank);
	local user_name: string = players:GetNameFromUserIdAsync(user_id);
	
	if (not user_name) then
		log(`JoinGroupAsync failure.`);
		return;
	end;
	new_data[tostring(group_id)].Members[tostring(user_id)] = {
		user_id = user_id;
		role_name = info.Name;
		role_index = index;
		user_name = players:GetNameFromUserIdAsync(user_id);
	};
	
	log(`[JoinGroupAsync] added {user_name} to group {group.GroupInfoAsyncResult.Name} as rank {info.Name}`);
	return;
end;

@native function pulse:RemoveGroup(group_id: number): ()
	assert(group_id and type(group_id) == "number", `RemoveGroup expects a number for group_id but got {typeof(group_id)}`);
	assert(is_studio, `RemoveGroup is restricted to only Studio.`);
	
	local group_data = new_data[tostring(group_id)];
	assert(group_data, `{group_id} is not a valid group.`);
	
	new_data[tostring(group_id)] = nil :: never;
	log(`Removed Group {group_data.GroupInfoAsyncResult.Name}`);
	
	return;
end;
@native function pulse:RankUserAsync(user_id: number, group_id: number, rank: string, caller: Player?): ()
	assert(user_id and type(user_id) == "number", `RankUserAsync expects a number for user_id but got {typeof(user_id)}`);
	assert(group_id and type(group_id) == "number", `RankUserAsync expects a number for group_id but got {typeof(group_id)}`);
	
	assert(rank and type(rank) == "string", `RankUserAsync expects a rank for rank but got {typeof(rank)}`);
	assert(new_data[tostring(group_id)], `RankUserAsync failed because provided group id {group_id} isn't registered by Pulse.`);
	
	assert(rank ~= "Guest", `Please use KickUserAsync if you wish to kick players from groups.`);
	assert(is_studio or caller ~= nil or typeof(caller) == "Instance" or not caller:IsA("Player"), "The caller parameter is required.");
	
	local group: mock_group = new_data[tostring(group_id)];
	local member_data = group.Members[tostring(user_id)] :: group_member;
	
	
	--[[for _: unknown, v in (group.Members) do
		if (v.user_id == user_id) then
			member_data = v :: group_member;
			if (not caller) then break; end;
		elseif (caller and v.user_id == caller.UserId) then
			caller_member_data = v :: group_member;
		end;
	end;]]
	assert(member_data, `{user_id} is not a member of group {group.GroupInfoAsyncResult.Name} {group_id}. Please use JoinGroupAsync if you wish to add new members to a group.`);
	
	if (caller) then
		local caller_member_data: group_member = group.Members[tostring(caller.UserId)];
		if (not caller_member_data or caller_member_data.role_index >= member_data.role_index or not has_permission(caller.UserId, "PERMISSION") and caller.UserId ~= game.CreatorId) then
			log(`Unauthroized rank set attempt from {caller} to {member_data.user_name}`);
			return;
		end;
	end;
	
	local index, role: {Rank: number, Name: string} = pulse.Helper.GetRoleInfo(group_id, rank);
	if (index == 0 or not role or role.Rank == 255 or member_data.user_id == group.Owner) then return; end;

	new_data[tostring(group_id)].Members[tostring(user_id)] = {
		user_id = user_id;
		role_name = role.Name;
		role_index = index;
		user_name = member_data.user_name;
	};
	log("Ranked", member_data.user_name, "in group", group.GroupInfoAsyncResult.Name, "to rank", role.Name);

	return;
end;
local existing_data = Handler("GetAsync", "Pulse");

if (existing_data) then
	new_data = existing_data;
end;
game:BindToClose(@native function(): ()
	if (is_studio and not pulse_config.save_in_studio) then log("save_in_studio is disabled, changes will not save.") return; end;
	Handler("SetAsync", "Pulse", new_data);
	return;
end);

return pulse;
