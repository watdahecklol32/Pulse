--!strict
--!native
local pulse = require("@self/Pulse");


pulse.MockGroup({
	[1] = {
		group_id = 35637063;
		Owner = game.CreatorId;
		Members = {{user_id = 1104970547, role_name = "Admins"}}
	};
});

print(pulse.Helper:GetRegisteredGroups())

local test: boolean = true;
if (test) then
	pulse:RankUserAsync(1104970547, 35637063, "Community");
end;

