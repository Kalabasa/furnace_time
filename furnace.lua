
--
-- Formspecs - copied from default:furnace
--

local function active_formspec(fuel_percent, item_percent)
	local formspec = 
		"size[8,8.5]"..
		default.gui_bg..
		default.gui_bg_img..
		default.gui_slots..
		"list[current_name;src;2.75,0.5;1,1;]"..
		"list[current_name;fuel;2.75,2.5;1,1;]"..
		"image[2.75,1.5;1,1;default_furnace_fire_bg.png^[lowpart:"..
		(100-fuel_percent)..":default_furnace_fire_fg.png]"..
		"image[3.75,1.5;1,1;gui_furnace_arrow_bg.png^[lowpart:"..
		(item_percent)..":gui_furnace_arrow_fg.png^[transformR270]"..
		"list[current_name;dst;4.75,0.96;2,2;]"..
		"list[current_player;main;0,4.25;8,1;]"..
		"list[current_player;main;0,5.5;8,3;8]"..
		default.get_hotbar_bg(0, 4.25)
	return formspec
end

local inactive_formspec =
	"size[8,8.5]"..
	default.gui_bg..
	default.gui_bg_img..
	default.gui_slots..
	"list[current_name;src;2.75,0.5;1,1;]"..
	"list[current_name;fuel;2.75,2.5;1,1;]"..
	"image[2.75,1.5;1,1;default_furnace_fire_bg.png]"..
	"image[3.75,1.5;1,1;gui_furnace_arrow_bg.png^[transformR270]"..
	"list[current_name;dst;4.75,0.96;2,2;]"..
	"list[current_player;main;0,4.25;8,1;]"..
	"list[current_player;main;0,5.5;8,3;8]"..
	default.get_hotbar_bg(0, 4.25)

--
-- ABM
--

local function swap_node(pos, name)
	local node = minetest.get_node(pos)
	if node.name == name then
		return
	end
	node.name = name
	minetest.swap_node(pos, node)
end

minetest.register_abm({
	nodenames = {"default:furnace", "default:furnace_active"},
	interval = 1.0,
	chance = 1,
	action = function(pos, node, active_object_count, active_object_count_wider)
		--
		-- Inizialize metadata
		--
		local meta = minetest.get_meta(pos)
		local fuel_time = meta:get_float("fuel_time") or 0
		local src_time = meta:get_float("src_time") or 0
		local fuel_totaltime = meta:get_float("fuel_totaltime") or 0
		local last_gametime = meta:get_float("last_gametime") or minetest.get_gametime()
		
		--
		-- Inizialize inventory
		--
		local inv = meta:get_inventory()
		for listname, size in pairs({
				src = 1,
				fuel = 1,
				dst = 4,
		}) do
			if inv:get_size(listname) ~= size then
				inv:set_size(listname, size)
			end
		end
		local srclist = inv:get_list("src")
		local fuellist = inv:get_list("fuel")
		local dstlist = inv:get_list("dst")
		
		--
		-- Cooking
		--

		-- Check if we have cookable content
		local cooked, aftercooked
		local cookable = true
		if furnace_time.compatibility then
			-- This check here can be removed (there is a check in the while loop) but the infotext needs the cooked and cookable variables in the function scope
			cooked, aftercooked = minetest.get_craft_result({method = "cooking", width = 1, items = srclist})
			cookable = cooked.time ~= 0
		end

		-- Get the time delta between last run
		local delta = minetest.get_gametime() - last_gametime
		last_gametime = minetest.get_gametime()

		if furnace_time.compatibility then
			-- The orignal default/furnace.lua ABM is still active! Subtract 1 second from the delta to take that into account.
			delta = delta - 1
		end
		
		-- Simulate the furnace for delta seconds
		while delta > 0 do
			-- Recheck if we still have cookable content
			cooked, aftercooked = minetest.get_craft_result({method = "cooking", width = 1, items = srclist})
			cookable = cooked.time ~= 0

			-- Determine appropriate time step size
			local step = delta
			local fuel_left = fuel_totaltime - fuel_time
			if fuel_totaltime ~= 0 then
				if fuel_left > 0 then
					-- There is fuel left, step to the time when the cookable item is ready OR when the fuel dies, whichever is nearest
					if cookable then
						local src_left = cooked.time - src_time
						step = math.min(delta, fuel_left, src_left)
					else
						step = math.min(delta, fuel_left)
					end
				elseif cookable then
					-- No fuel left, replacing costs 1 second
					step = 1
				end
			end
			delta = delta - step

			-- Check if we have enough fuel to burn
			if fuel_time < fuel_totaltime then
				-- The furnace is currently active and has enough fuel
				fuel_time = fuel_time + step
				
				-- If there is a cookable item then check if it is ready yet
				if cookable then
					src_time = src_time + step
					if src_time >= cooked.time then
						-- Place result in dst list if possible
						if inv:room_for_item("dst", cooked.item) then
							inv:add_item("dst", cooked.item)
							inv:set_stack("src", 1, aftercooked.items[1])
							srclist = inv:get_list("src")
							src_time = 0
						end
					end
				end
			else
				-- Furnace ran out of fuel
				if cookable then
					-- We need to get new fuel
					local fuel, afterfuel = minetest.get_craft_result({method = "fuel", width = 1, items = fuellist})
					
					if fuel.time == 0 then
						-- No valid fuel in fuel list
						fuel_totaltime = 0
						fuel_time = 0
						src_time = 0
					else
						-- Take fuel from fuel list
						inv:set_stack("fuel", 1, afterfuel.items[1])
						fuellist = inv:get_list("fuel")
						
						fuel_totaltime = fuel.time
						fuel_time = 0
						
					end
				else
					-- We don't need to get new fuel since there is no cookable item
					fuel_totaltime = 0
					fuel_time = 0
					src_time = 0
				end
			end
		end
		
		--
		-- Update formspec, infotext and node
		--
		local formspec = inactive_formspec
		local item_state = ""
		local item_percent = 0
		if cookable then
			item_percent =  math.floor(src_time / cooked.time * 100)
			item_state = item_percent .. "%"
		else
			if srclist[1]:is_empty() then
				item_state = "Empty"
			else
				item_state = "Not cookable"
			end
		end
		
		local fuel_state = "Empty"
		local active = "inactive "
		if fuel_time <= fuel_totaltime and fuel_totaltime ~= 0 then
			active = "active "
			local fuel_percent = math.floor(fuel_time / fuel_totaltime * 100)
			fuel_state = fuel_percent .. "%"
			formspec = active_formspec(fuel_percent, item_percent)
			swap_node(pos, "default:furnace_active")
		else
			if not fuellist[1]:is_empty() then
				fuel_state = "0%"
			end
			swap_node(pos, "default:furnace")
		end
		
		local infotext =  "Furnace " .. active .. "(Item: " .. item_state .. "; Fuel: " .. fuel_state .. ")"
		
		--
		-- Set meta values
		--
		meta:set_float("last_gametime", last_gametime)
		meta:set_float("fuel_totaltime", fuel_totaltime)
		meta:set_float("fuel_time", fuel_time)
		meta:set_float("src_time", src_time)
		meta:set_string("formspec", formspec)
		meta:set_string("infotext", infotext)
	end,
})
