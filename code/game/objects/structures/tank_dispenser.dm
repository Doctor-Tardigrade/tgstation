#define TANK_DISPENSER_CAPACITY 10

/obj/structure/dispenser
	name = "tank storage unit"
	desc = "A simple yet bulky storage device for gas tanks. Has room for up to ten oxygen tanks, and ten plasma tanks."
	icon = 'icons/obj/objects.dmi'
	icon_state = "dispenser"
	density = 1
	anchored = 1
	var/oxygentanks = TANK_DISPENSER_CAPACITY
	var/plasmatanks = TANK_DISPENSER_CAPACITY

/obj/structure/dispenser/oxygen
	plasmatanks = 0

/obj/structure/dispenser/plasma
	oxygentanks = 0

/obj/structure/dispenser/New()
	for(var/i in 1 to oxygentanks)
		new /obj/item/weapon/tank/internals/oxygen(src)
	for(var/i in 1 to plasmatanks)
		new /obj/item/weapon/tank/internals/plasma(src)
	update_icon()

/obj/structure/dispenser/update_icon()
	overlays.Cut()
	switch(oxygentanks)
		if(1 to 3)
			overlays += "oxygen-[oxygentanks]"
		if(4 to TANK_DISPENSER_CAPACITY)
			overlays += "oxygen-4"
	switch(plasmatanks)
		if(1 to 4)
			overlays += "plasma-[plasmatanks]"
		if(5 to TANK_DISPENSER_CAPACITY)
			overlays += "plasma-5"

/obj/structure/dispenser/attackby(obj/item/I, mob/user, params)
	var/full
	if(istype(I, /obj/item/weapon/tank/internals/plasma))
		if(plasmatanks < TANK_DISPENSER_CAPACITY)
			plasmatanks++
		else
			full = TRUE
	else if(istype(I, /obj/item/weapon/tank/internals/oxygen))
		if(oxygentanks < TANK_DISPENSER_CAPACITY)
			oxygentanks++
		else
			full = TRUE
	else
		user << "<span class='notice'>[I] does not fit into [src].</span>"
		return
	if(full)
		user << "<span class='notice'>[src] can't hold anymore of [I].</span>"
		return

	if(!user.drop_item())
		return
	I.loc = src
	user << "<span class='notice'>You put [I] in [src].</span>"

/obj/structure/dispenser/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = 0, \
										datum/tgui/master_ui = null, datum/ui_state/state = physical_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "tank_dispenser", name, 275, 100, master_ui, state)
		ui.open()

/obj/structure/dispenser/get_ui_data(mob/user)
	var/list/data = list()
	data["oxygen"] = oxygentanks
	data["plasma"] = plasmatanks

	return data

/obj/structure/dispenser/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("plasma")
			var/obj/item/weapon/tank/internals/plasma/tank = locate() in src
			if(tank && usr.put_in_any_hand_if_possible(tank))
				plasmatanks--
			. = TRUE
		if("oxygen")
			var/obj/item/weapon/tank/internals/oxygen/tank = locate() in src
			if(tank && usr.put_in_any_hand_if_possible(tank))
				oxygentanks--
			. = TRUE
	update_icon()

#undef TANK_DISPENSER_CAPACITY