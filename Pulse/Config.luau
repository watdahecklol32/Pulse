return{
	max_retries = 6; -- Retry count if datastore errors.
	yield_time = 2; -- Retry wait time.
	save_in_studio = true; -- Save PULSE groups to datastore.
	Permissions = {
		ALL = {game.CreatorId}; -- Unrestricted permission
		GROUP = {}; -- Set ranks
	}
};
