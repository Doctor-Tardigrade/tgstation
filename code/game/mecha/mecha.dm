#define MECHA_INT_FIRE 1
#define MECHA_INT_TEMP_CONTROL 2
#define MECHA_INT_SHORT_CIRCUIT 4
#define MECHA_INT_TANK_BREACH 8
#define MECHA_INT_CONTROL_LOST 16

#define MELEE 1
#define RANGED 2


/obj/mecha
	name = "mecha"
	desc = "Exosuit"
	icon = 'icons/mecha/mecha.dmi'
	density = 1 //Dense. To raise the heat.
	opacity = 1 ///opaque. Menacing.
	anchored = 1 //no pulling around.
	unacidable = 1 //and no deleting hoomans inside
	layer = MOB_LAYER - 0.2//icon draw layer
	infra_luminosity = 15 //byond implementation is bugged.
	force = 5
	var/can_move = 1
	var/mob/living/carbon/occupant = null
	var/step_in = 10 //make a step in step_in/10 sec.
	var/dir_in = 2//What direction will the mech face when entered/powered on? Defaults to South.
	var/step_energy_drain = 10
	var/health = 300 //health is health
	var/deflect_chance = 10 //chance to deflect the incoming projectiles, hits, or lesser the effect of ex_act.
	//the values in this list show how much damage will pass through, not how much will be absorbed.
	var/list/damage_absorption = list("brute"=0.8,"fire"=1.2,"bullet"=0.9,"laser"=1,"energy"=1,"bomb"=1)
	var/obj/item/weapon/stock_parts/cell/cell
	var/state = 0
	var/list/log = new
	var/last_message = 0
	var/add_req_access = 1
	var/maint_access = 0
	var/dna	//dna-locking the mech
	var/list/proc_res = list() //stores proc owners, like proc_res["functionname"] = owner reference
	var/datum/effect/effect/system/spark_spread/spark_system = new
	var/lights = 0
	var/lights_power = 6
	var/last_user_hud = 1 // used to show/hide the mecha hud while preserving previous preference

	//inner atmos
	var/use_internal_tank = 0
	var/internal_tank_valve = ONE_ATMOSPHERE
	var/obj/machinery/portable_atmospherics/canister/internal_tank
	var/datum/gas_mixture/cabin_air
	var/obj/machinery/atmospherics/components/unary/portables_connector/connected_port = null

	var/obj/item/device/radio/radio = null

	var/max_temperature = 25000
	var/internal_damage_threshold = 50 //health percentage below which internal damage is possible
	var/internal_damage = 0 //contains bitflags

	var/list/operation_req_access = list()//required access level for mecha operation
	var/list/internals_req_access = list(access_engine,access_robotics)//required access level to open cell compartment

	var/wreckage

	var/list/equipment = new
	var/obj/item/mecha_parts/mecha_equipment/selected
	var/max_equip = 3
	var/datum/events/events

	var/stepsound = 'sound/mecha/mechstep.ogg'
	var/turnsound = 'sound/mecha/mechturn.ogg'

	var/melee_cooldown = 10
	var/melee_can_hit = 1

	var/datum/action/mecha/mech_eject/eject_action = new
	var/datum/action/mecha/mech_toggle_internals/internals_action = new
	var/datum/action/mecha/mech_cycle_equip/cycle_action = new
	var/datum/action/mecha/mech_toggle_lights/lights_action = new
	var/datum/action/mecha/mech_view_stats/stats_action = new


/obj/mecha/New()
	..()
	events = new
	icon_state += "-open"
	add_radio()
	add_cabin()
	add_airtank()
	spark_system.set_up(2, 0, src)
	spark_system.attach(src)
	add_cell()
	SSobj.processing |= src
	log_message("[src.name] created.")
	mechas_list += src //global mech list
	return

/obj/mecha/Destroy()
	go_out()
	for(var/mob/M in src) //Let's just be ultra sure
		if(isAI(M))
			M.gib() //AIs are loaded into the mech computer itself. When the mech dies, so does the AI. Forever.
		else
			M.Move(loc)

	if(prob(30))
		explosion(get_turf(loc), 0, 0, 1, 3)

	if(wreckage)
		var/obj/structure/mecha_wreckage/WR = new wreckage(loc)
		for(var/obj/item/mecha_parts/mecha_equipment/E in equipment)
			if(E.salvageable && prob(30))
				WR.crowbar_salvage += E
				E.detach(WR) //detaches from src into WR
				E.equip_ready = 1
				E.reliability = round(rand(E.reliability/3,E.reliability))
			else
				E.detach(loc)
				qdel(E)
		if(cell)
			WR.crowbar_salvage += cell
			cell.forceMove(WR)
			cell.charge = rand(0, cell.charge)
		if(internal_tank)
			WR.crowbar_salvage += internal_tank
			internal_tank.forceMove(WR)
	else
		for(var/obj/item/mecha_parts/mecha_equipment/E in equipment)
			E.detach(loc)
			qdel(E)
		if(cell)
			qdel(cell)
		if(internal_tank)
			qdel(internal_tank)
	SSobj.processing.Remove(src)
	equipment.Cut()
	cell = null
	internal_tank = null
	if(loc)
		loc.assume_air(cabin_air)
		air_update_turf()
	else
		del(cabin_air)
	cabin_air = null
	qdel(spark_system)
	spark_system = null

	mechas_list -= src //global mech list
	return ..()

////////////////////////
////// Helpers /////////
////////////////////////

/obj/mecha/proc/add_airtank()
	internal_tank = new /obj/machinery/portable_atmospherics/canister/air(src)
	return internal_tank

/obj/mecha/proc/add_cell(var/obj/item/weapon/stock_parts/cell/C=null)
	if(C)
		C.forceMove(src)
		cell = C
		return
	cell = new(src)
	cell.charge = 15000
	cell.maxcharge = 15000

/obj/mecha/proc/add_cabin()
	cabin_air = new
	cabin_air.temperature = T20C
	cabin_air.volume = 200
	cabin_air.oxygen = O2STANDARD*cabin_air.volume/(R_IDEAL_GAS_EQUATION*cabin_air.temperature)
	cabin_air.nitrogen = N2STANDARD*cabin_air.volume/(R_IDEAL_GAS_EQUATION*cabin_air.temperature)
	return cabin_air

/obj/mecha/proc/add_radio()
	radio = new(src)
	radio.name = "[src] radio"
	radio.icon = icon
	radio.icon_state = icon_state
	radio.subspace_transmission = 1

/obj/mecha/proc/can_use(mob/user)
	if(user != occupant)
		return 0
	if(user && ismob(user))
		if(!user.incapacitated())
			return 1
	return 0

////////////////////////////////////////////////////////////////////////////////

/obj/mecha/examine(mob/user)
	..()
	var/integrity = health/initial(health)*100
	switch(integrity)
		if(85 to 100)
			user << "It's fully intact."
		if(65 to 85)
			user << "It's slightly damaged."
		if(45 to 65)
			user << "It's badly damaged."
		if(25 to 45)
			user << "It's heavily damaged."
		else
			user << "It's falling apart."
	if(equipment && equipment.len)
		user << "It's equipped with:"
		for(var/obj/item/mecha_parts/mecha_equipment/ME in equipment)
			user << "\icon[ME] [ME]"
	return


//processing internal damage, temperature, air regulation, alert updates, lights power use.
/obj/mecha/process()

	var/internal_temp_regulation = 1

	if(internal_damage)

		if(internal_damage & MECHA_INT_FIRE)
			if(!(internal_damage & MECHA_INT_TEMP_CONTROL) && prob(5))
				clearInternalDamage(MECHA_INT_FIRE)
			if(internal_tank)
				if(internal_tank.return_pressure() > internal_tank.maximum_pressure && !(internal_damage & MECHA_INT_TANK_BREACH))
					setInternalDamage(MECHA_INT_TANK_BREACH)
				var/datum/gas_mixture/int_tank_air = internal_tank.return_air()
				if(int_tank_air && int_tank_air.return_volume()>0) //heat the air_contents
					int_tank_air.temperature = min(6000+T0C, int_tank_air.temperature+rand(10,15))
			if(cabin_air && cabin_air.return_volume()>0)
				cabin_air.temperature = min(6000+T0C, cabin_air.return_temperature()+rand(10,15))
				if(cabin_air.return_temperature() > max_temperature/2)
					take_damage(4/round(max_temperature/cabin_air.return_temperature(),0.1),"fire")

		if(internal_damage & MECHA_INT_TEMP_CONTROL)
			internal_temp_regulation = 0

		if(internal_damage & MECHA_INT_TANK_BREACH) //remove some air from internal tank
			if(internal_tank)
				var/datum/gas_mixture/int_tank_air = internal_tank.return_air()
				var/datum/gas_mixture/leaked_gas = int_tank_air.remove_ratio(0.10)
				if(loc)
					loc.assume_air(leaked_gas)
					air_update_turf()
				else
					del(leaked_gas)

		if(internal_damage & MECHA_INT_SHORT_CIRCUIT)
			if(get_charge())
				spark_system.start()
				cell.charge -= min(20,cell.charge)
				cell.maxcharge -= min(20,cell.maxcharge)

	if(internal_temp_regulation)
		if(cabin_air && cabin_air.return_volume() > 0)
			var/delta = cabin_air.temperature - T20C
			cabin_air.temperature -= max(-10, min(10, round(delta/4,0.1)))

	if(internal_tank)
		var/datum/gas_mixture/tank_air = internal_tank.return_air()

		var/release_pressure = internal_tank_valve
		var/cabin_pressure = cabin_air.return_pressure()
		var/pressure_delta = min(release_pressure - cabin_pressure, (tank_air.return_pressure() - cabin_pressure)/2)
		var/transfer_moles = 0
		if(pressure_delta > 0) //cabin pressure lower than release pressure
			if(tank_air.return_temperature() > 0)
				transfer_moles = pressure_delta*cabin_air.return_volume()/(cabin_air.return_temperature() * R_IDEAL_GAS_EQUATION)
				var/datum/gas_mixture/removed = tank_air.remove(transfer_moles)
				cabin_air.merge(removed)
		else if(pressure_delta < 0) //cabin pressure higher than release pressure
			var/datum/gas_mixture/t_air = return_air()
			pressure_delta = cabin_pressure - release_pressure
			if(t_air)
				pressure_delta = min(cabin_pressure - t_air.return_pressure(), pressure_delta)
			if(pressure_delta > 0) //if location pressure is lower than cabin pressure
				transfer_moles = pressure_delta*cabin_air.return_volume()/(cabin_air.return_temperature() * R_IDEAL_GAS_EQUATION)
				var/datum/gas_mixture/removed = cabin_air.remove(transfer_moles)
				if(t_air)
					t_air.merge(removed)
				else //just delete the cabin gas, we're in space or some shit
					del(removed)

	if(occupant)
		if(cell)
			var/cellcharge = cell.charge/cell.maxcharge
			switch(cellcharge)
				if(0.75 to INFINITY)
					occupant.clear_alert("charge")
				if(0.5 to 0.75)
					occupant.throw_alert("charge","lowcell",1)
				if(0.25 to 0.5)
					occupant.throw_alert("charge","lowcell",2)
				if(0.01 to 0.25)
					occupant.throw_alert("charge","lowcell",3)
				else
					occupant.throw_alert("charge","emptycell")

		var/integrity = health/initial(health)*100
		switch(integrity)
			if(30 to 45)
				occupant.throw_alert("mech damage", "low_mech_integrity", 1)
			if(15 to 35)
				occupant.throw_alert("mech damage", "low_mech_integrity", 2)
			if(-INFINITY to 15)
				occupant.throw_alert("mech damage", "low_mech_integrity", 3)
			else
				occupant.clear_alert("mech damage")

		if(occupant.loc != src) //something went wrong
			occupant.clear_alert("charge")
			occupant.clear_alert("mech damage")
			RemoveActions(occupant, human_occupant=1)
			occupant = null

	if(lights)
		var/lights_energy_drain = 2
		use_power(lights_energy_drain)




/obj/mecha/proc/drop_item()//Derpfix, but may be useful in future for engineering exosuits.
	return

/obj/mecha/Hear(message, atom/movable/speaker, message_langs, raw_message, radio_freq, list/spans)
	if(speaker == occupant && radio.broadcasting)
		radio.talk_into(speaker, text, , spans)
	return

////////////////////////////
///// Action processing ////
////////////////////////////


/obj/mecha/proc/click_action(atom/target,mob/user)
	if(!occupant || occupant != user )
		return
	if(!locate(/turf) in list(target,target.loc)) // Prevents inventory from being drilled
		return
	if(user.incapacitated())
		return
	if(state)
		occupant_message("<span class='warning'>Maintenance protocols in effect.</span>")
		return
	if(!get_charge())
		return
	if(src == target)
		return
	var/dir_to_target = get_dir(src,target)
	if(dir_to_target && !(dir_to_target & src.dir))//wrong direction
		return
	if(internal_damage & MECHA_INT_CONTROL_LOST)
		target = safepick(view(3,target))
		if(!target)
			return
	if(!target.Adjacent(src))
		if(selected && selected.is_ranged())
			if(selected.action(target))
				selected.start_cooldown()
	else if(selected && selected.is_melee())
		if(selected.action(target))
			selected.start_cooldown()
	else
		if(internal_damage & MECHA_INT_CONTROL_LOST)
			target = safepick(oview(1,src))
		if(!melee_can_hit || !istype(target, /atom))
			return
		target.mech_melee_attack(src)
		melee_can_hit = 0
		spawn(melee_cooldown)
			melee_can_hit = 1
	return


/obj/mecha/proc/range_action(atom/target)
	return


//////////////////////////////////
////////  Movement procs  ////////
//////////////////////////////////

/obj/mecha/Move(atom/newloc, direct)
	. = ..()
	if(.)
		events.fireEvent("onMove",get_turf(src))

/obj/mecha/Process_Spacemove(var/movement_dir = 0)
	if(occupant)
		return occupant.Process_Spacemove(movement_dir) //We'll just say you used the clamp to grab the wall
	return ..()

/obj/mecha/relaymove(mob/user,direction)
	if(!direction)
		return
	if(user != src.occupant) //While not "realistic", this piece is player friendly.
		user.forceMove(get_turf(src))
		user << "<span class='notice'>You climb out from [src].</span>"
		return 0
	if(connected_port)
		if(world.time - last_message > 20)
			src.occupant_message("<span class='warning'>Unable to move while connected to the air system port!</span>")
			last_message = world.time
		return 0
	if(state)
		occupant_message("<span class='danger'>Maintenance protocols in effect.</span>")
		return
	return domove(direction)

/obj/mecha/proc/domove(direction)
	if(!can_move)
		return 0
	if(!Process_Spacemove(direction))
		return 0
	if(!has_charge(step_energy_drain))
		return 0
	var/move_result = 0
	if(internal_damage & MECHA_INT_CONTROL_LOST)
		move_result = mechsteprand()
	else if(src.dir!=direction)
		move_result = mechturn(direction)
	else
		move_result = mechstep(direction)
	if(move_result)
		use_power(step_energy_drain)
		can_move = 0
		spawn(step_in)
			can_move = 1
		return 1
	return 0

/obj/mecha/proc/mechturn(direction)
	dir = direction
	if(turnsound)
		playsound(src,turnsound,40,1)
	return 1

/obj/mecha/proc/mechstep(direction)
	var/result = step(src,direction)
	if(result && stepsound)
		playsound(src,stepsound,40,1)
	return result

/obj/mecha/proc/mechsteprand()
	var/result = step_rand(src)
	if(result && stepsound)
		playsound(src,stepsound,40,1)
	return result

/obj/mecha/Bump(var/atom/obstacle)
//	src.inertia_dir = null
	if(istype(obstacle, /obj))
		var/obj/O = obstacle
		if(istype(O, /obj/effect/portal)) //derpfix
			anchored = 0
			O.Crossed(src)
			src.anchored = 1
		else if(!O.anchored)
			step(obstacle, dir)
		else //I have no idea why I disabled this
			obstacle.Bumped(src)
	else if(istype(obstacle, /mob))
		step(obstacle, dir)
	else
		obstacle.Bumped(src)
	return

///////////////////////////////////
////////  Internal damage  ////////
///////////////////////////////////

/obj/mecha/proc/check_for_internal_damage(list/possible_int_damage,ignore_threshold=null)
	if(!islist(possible_int_damage) || isemptylist(possible_int_damage)) return
	if(prob(20))
		if(ignore_threshold || health*100/initial(health) < internal_damage_threshold)
			for(var/T in possible_int_damage)
				if(internal_damage & T)
					possible_int_damage -= T
			var/int_dam_flag = safepick(possible_int_damage)
			if(int_dam_flag)
				setInternalDamage(int_dam_flag)
	if(prob(5))
		if(ignore_threshold || src.health*100/initial(src.health)<src.internal_damage_threshold)
			var/obj/item/mecha_parts/mecha_equipment/ME = safepick(equipment)
			if(ME)
				qdel(ME)
	return

/obj/mecha/proc/setInternalDamage(int_dam_flag)
	internal_damage |= int_dam_flag
	log_append_to_last("Internal damage of type [int_dam_flag].",1)
	occupant << sound('sound/machines/warning-buzzer.ogg',wait=0)
	return

/obj/mecha/proc/clearInternalDamage(int_dam_flag)
	if(internal_damage & int_dam_flag)
		switch(int_dam_flag)
			if(MECHA_INT_TEMP_CONTROL)
				occupant_message("<span class='boldnotice'>Life support system reactivated.</span>")
			if(MECHA_INT_FIRE)
				occupant_message("<span class='boldnotice'>Internal fire extinquished.</span>")
			if(MECHA_INT_TANK_BREACH)
				occupant_message("<span class='boldnotice'>Damaged internal tank has been sealed.</span>")
	internal_damage &= ~int_dam_flag


/////////////////////////////////////
//////////// AI piloting ////////////
/////////////////////////////////////

/obj/mecha/attack_ai(mob/living/silicon/ai/user)
	if(!isAI(user))
		return
	//Allows the Malf to scan a mech's status and loadout, helping it to decide if it is a worthy chariot.
	if(user.can_dominate_mechs)
		examine(user) //Get diagnostic information!
		var/obj/item/mecha_parts/mecha_tracking/B = locate(/obj/item/mecha_parts/mecha_tracking) in src
		if(B) //Beacons give the AI more detailed mech information.
			user << "<span class='danger'>Warning: Tracking Beacon detected. Enter at your own risk. Beacon Data:"
			user << "[B.get_mecha_info()]"
		//Nothing like a big, red link to make the player feel powerful!
		user << "<a href='?src=\ref[user];ai_take_control=\ref[src]'><span class='userdanger'>ASSUME DIRECT CONTROL?</span></a><br>"

/obj/mecha/transfer_ai(interaction, mob/user, mob/living/silicon/ai/AI, obj/item/device/aicard/card)
	if(!..())
		return

 //Transfer from core or card to mech. Proc is called by mech.
	switch(interaction)
		if(AI_TRANS_TO_CARD) //Upload AI from mech to AI card.
			if(!state) //Mech must be in maint mode to allow carding.
				user << "<span class='warning'>[name] must have maintenance protocols active in order to allow a transfer.</span>"
				return
			AI = occupant
			if(!AI || !isAI(occupant)) //Mech does not have an AI for a pilot
				user << "<span class='warning'>No AI detected in the [name] onboard computer.</span>"
				return
			if (AI.mind.special_role == "malfunction") //Malf AIs cannot leave mechs. Except through death.
				user << "<span class='boldannounce'>ACCESS DENIED.</span>"
				return
			AI.aiRestorePowerRoutine = 0//So the AI initially has power.
			AI.control_disabled = 1
			AI.radio_enabled = 0
			AI.loc = card
			occupant = null
			AI.controlled_mech = null
			AI.remote_control = null
			icon_state = initial(icon_state)+"-open"
			AI << "You have been downloaded to a mobile storage device. Wireless connection offline."
			user << "<span class='boldnotice'>Transfer successful</span>: [AI.name] ([rand(1000,9999)].exe) removed from [name] and stored within local memory."

		if(AI_MECH_HACK) //Called by Malf AI mob on the mech.
			new /obj/structure/AIcore/deactivated(AI.loc)
			if(occupant) //Oh, I am sorry, were you using that?
				AI << "<span class='warning'>Pilot detected! Forced ejection initiated!"
				occupant << "<span class='danger'>You have been forcibly ejected!</span>"
				go_out(1) //IT IS MINE, NOW. SUCK IT, RD!
			ai_enter_mech(AI, interaction)

		if(AI_TRANS_FROM_CARD) //Using an AI card to upload to a mech.
			AI = locate(/mob/living/silicon/ai) in card
			if(!AI)
				user << "<span class='warning'>There is no AI currently installed on this device.</span>"
				return
			else if(AI.stat || !AI.client)
				user << "<span class='warning'>[AI.name] is currently unresponsive, and cannot be uploaded.</span>"
				return
			else if(occupant || dna) //Normal AIs cannot steal mechs!
				user << "<span class='warning'>Access denied. [name] is [occupant ? "currently occupied" : "secured with a DNA lock"]."
				return
			AI.control_disabled = 0
			AI.radio_enabled = 1
			user << "<span class='boldnotice'>Transfer successful</span>: [AI.name] ([rand(1000,9999)].exe) installed and executed successfully. Local copy has been removed."
			ai_enter_mech(AI, interaction)

//Hack and From Card interactions share some code, so leave that here for both to use.
/obj/mecha/proc/ai_enter_mech(mob/living/silicon/ai/AI, interaction)
	AI.aiRestorePowerRoutine = 0
	AI.loc = src
	occupant = AI
	icon_state = initial(icon_state)
	playsound(src, 'sound/machines/windowdoor.ogg', 50, 1)
	if(!internal_damage)
		occupant << sound('sound/mecha/nominal.ogg',volume=50)
	AI.cancel_camera()
	AI.controlled_mech = src
	AI.remote_control = src
	AI.canmove = 1 //Much easier than adding AI checks! Be sure to set this back to 0 if you decide to allow an AI to leave a mech somehow.
	AI.can_shunt = 0 //ONE AI ENTERS. NO AI LEAVES.
	AI << "[interaction == AI_MECH_HACK ? "<span class='announce'>Takeover of [name] complete! You are now permanently loaded onto the onboard computer. Do not attempt to leave the station sector!</span>" \
	: "<span class='notice'>You have been uploaded to a mech's onboard computer."]"
	AI << "<span class='boldnotice'>Use Middle-Mouse to activate mech functions and equipment. Click normally for AI interactions.</span>"
	GrantActions(AI)

/////////////////////////////////////
////////  Atmospheric stuff  ////////
/////////////////////////////////////

/obj/mecha/remove_air(amount)
	if(use_internal_tank)
		return cabin_air.remove(amount)
	return ..()

/obj/mecha/return_air()
	if(use_internal_tank)
		return cabin_air
	return ..()

/obj/mecha/proc/return_pressure()
	var/datum/gas_mixture/t_air = return_air()
	if(t_air)
		. = t_air.return_pressure()
	return


/obj/mecha/proc/return_temperature()
	var/datum/gas_mixture/t_air = return_air()
	if(t_air)
		. = t_air.return_temperature()
	return

/obj/mecha/proc/connect(obj/machinery/atmospherics/components/unary/portables_connector/new_port)
	//Make sure not already connected to something else
	if(connected_port || !new_port || new_port.connected_device)
		return 0

	//Make sure are close enough for a valid connection
	if(new_port.loc != src.loc)
		return 0

	//Perform the connection
	connected_port = new_port
	connected_port.connected_device = src
	var/datum/pipeline/connected_port_parent = connected_port.parents["p1"]
	connected_port_parent.reconcile_air()

	log_message("Connected to gas port.")
	return 1

/obj/mecha/proc/disconnect()
	if(!connected_port)
		return 0

	connected_port.connected_device = null
	connected_port = null
	src.log_message("Disconnected from gas port.")
	return 1

/obj/mecha/portableConnectorReturnAir()
	return internal_tank.return_air()


/obj/mecha/MouseDrop_T(mob/M, mob/user)
	if (!user.canUseTopic(src) || (user != M))
		return
	if(!ishuman(user)) // no silicons or drones in mechas.
		return
	log_message("[user] tries to move in.")
	if (occupant)
		usr << "<span class='warning'>The [name] is already occupied!</span>"
		log_append_to_last("Permission denied.")
		return
	var/passed
	if(dna)
		if(check_dna_integrity(user))
			var/mob/living/carbon/C = user
			if(C.dna.unique_enzymes==src.dna)
				passed = 1
	else if(operation_allowed(user))
		passed = 1
	if(!passed)
		user << "<span class='warning'>Access denied.</span>"
		log_append_to_last("Permission denied.")
		return
	for(var/mob/living/simple_animal/slime/S in range(1,user))
		if(S.Victim == user)
			user << "<span class='warning'>You're too busy getting your life sucked out of you!</span>"
			return

	visible_message("[user] starts to climb into [src.name].")

	if(do_after(user, 40, target = src))
		if(health <= 0)
			user << "<span class='warning'>You cannot get in the [src.name], it has been destroyed!</span>"
		else if(occupant)
			user << "<span class='danger'>[src.occupant] was faster! Try better next time, loser.</span>"
		else
			moved_inside(user)
	else
		user << "<span class='warning'>You stop entering the exosuit!</span>"
	return

/obj/mecha/proc/moved_inside(mob/living/carbon/human/H)
	if(H && H.client && H in range(1))
		H.reset_view(src)
		H.stop_pulling()
		H.forceMove(src)
		occupant = H
		add_fingerprint(H)
		GrantActions(H, human_occupant=1)
		forceMove(loc)
		log_append_to_last("[H] moved in as pilot.")
		icon_state = initial(icon_state)
		dir = dir_in
		playsound(src, 'sound/machines/windowdoor.ogg', 50, 1)
		if(!internal_damage)
			occupant << sound('sound/mecha/nominal.ogg',volume=50)
		return 1
	else
		return 0

/obj/mecha/proc/mmi_move_inside(obj/item/device/mmi/mmi_as_oc,mob/user)
	if(!mmi_as_oc.brainmob || !mmi_as_oc.brainmob.client)
		user << "<span class='warning'>Consciousness matrix not detected!</span>"
		return 0
	else if(mmi_as_oc.brainmob.stat)
		user << "<span class='warning'>Beta-rhythm below acceptable level!</span>"
		return 0
	else if(occupant)
		user << "<span class='warning'>Occupant detected!</span>"
		return 0
	else if(dna && dna!=mmi_as_oc.brainmob.dna.unique_enzymes)
		user << "<span class='warning'>Stop it!</span>"
		return 0

	visible_message("<span class='notice'>[user] starts to insert an MMI into [src.name].</span>")

	if(do_after(user, 40, target = src))
		if(!occupant)
			return mmi_moved_inside(mmi_as_oc,user)
		else
			user << "<span class='warning'>Occupant detected!</span>"
	else
		user << "<span class='notice'>You stop inserting the MMI.</span>"
	return 0

/obj/mecha/proc/mmi_moved_inside(obj/item/device/mmi/mmi_as_oc,mob/user)
	if(mmi_as_oc && user in range(1))
		if(!mmi_as_oc.brainmob || !mmi_as_oc.brainmob.client)
			user << "<span class='notice'>Consciousness matrix not detected!</span>"
			return 0
		else if(mmi_as_oc.brainmob.stat)
			user << "<span class='warning'>Beta-rhythm below acceptable level!</span>"
			return 0
		if(!user.unEquip(mmi_as_oc))
			user << "<span class='warning'>\the [mmi_as_oc] is stuck to your hand, you cannot put it in \the [src]!</span>"
			return
		var/mob/brainmob = mmi_as_oc.brainmob
		brainmob.reset_view(src)
		occupant = brainmob
		brainmob.loc = src //should allow relaymove
		brainmob.canmove = 1
		mmi_as_oc.loc = src
		mmi_as_oc.mecha = src
		icon_state = initial(icon_state)
		dir = dir_in
		log_message("[mmi_as_oc] moved in as pilot.")
		if(!internal_damage)
			occupant << sound('sound/mecha/nominal.ogg',volume=50)
		GrantActions(brainmob)
		return 1
	else
		return 0

/obj/mecha/container_resist()
	go_out()


/obj/mecha/Exited(atom/movable/M, atom/newloc)
	if(occupant && occupant == M) // The occupant exited the mech without calling go_out()
		go_out(1, newloc)

/obj/mecha/proc/go_out(var/forced, var/atom/newloc = loc)
	if(!occupant)
		return
	var/atom/movable/mob_container
	occupant.clear_alert("charge")
	occupant.clear_alert("mech damage")
	if(ishuman(occupant))
		mob_container = occupant
		RemoveActions(occupant, human_occupant=1)
	else if(istype(occupant, /mob/living/carbon/brain))
		var/mob/living/carbon/brain/brain = occupant
		RemoveActions(brain)
		mob_container = brain.container
	else if(isAI(occupant) && forced) //This should only happen if there are multiple AIs in a round, and at least one is Malf.
		RemoveActions(occupant)
		occupant.gib()  //If one Malf decides to steal a mech from another AI (even other Malfs!), they are destroyed, as they have nowhere to go when replaced.
		occupant = null
		return
	else
		return
	var/mob/living/L = occupant
	occupant = null //we need it null when forceMove calls Exited().
	if(mob_container.forceMove(newloc))//ejecting mob container
		log_message("[mob_container] moved out.")
		L.reset_view()
		L << browse(null, "window=exosuit")


		if(istype(mob_container, /obj/item/device/mmi))
			var/obj/item/device/mmi/mmi = mob_container
			if(mmi.brainmob)
				L.loc = mmi
			mmi.mecha = null
			mmi.update_icon()
			L.canmove = 0
		icon_state = initial(icon_state)+"-open"
		dir = dir_in
	return

/////////////////////////
////// Access stuff /////
/////////////////////////

/obj/mecha/proc/operation_allowed(mob/M)
	req_access = operation_req_access
	req_one_access = list()
	return allowed(M)

/obj/mecha/proc/internals_access_allowed(mob/M)
	req_one_access = internals_req_access
	req_access = list()
	return allowed(M)



////////////////////////////////
/////// Messages and Log ///////
////////////////////////////////

/obj/mecha/proc/occupant_message(message as text)
	if(message)
		if(src.occupant && src.occupant.client)
			src.occupant << "\icon[src] [message]"
	return

/obj/mecha/proc/log_message(message as text,red=null)
	log.len++
	log[log.len] = list("time"="[worldtime2text()]","date","year"="[year_integer+540]","message"="[red?"<font color='red'>":null][message][red?"</font>":null]")
	return log.len

/obj/mecha/proc/log_append_to_last(message as text,red=null)
	var/list/last_entry = src.log[src.log.len]
	last_entry["message"] += "<br>[red?"<font color='red'>":null][message][red?"</font>":null]"
	return

var/year = time2text(world.realtime,"YYYY")
var/year_integer = text2num(year) // = 2013???

///////////////////////
///// Power stuff /////
///////////////////////

/obj/mecha/proc/has_charge(amount)
	return (get_charge()>=amount)

/obj/mecha/proc/get_charge()
	for(var/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay/R in equipment)
		var/relay_charge = R.get_charge()
		if(relay_charge)
			return relay_charge
	if(cell)
		return max(0, cell.charge)

/obj/mecha/proc/use_power(amount)
	if(get_charge())
		cell.use(amount)
		return 1
	return 0

/obj/mecha/proc/give_power(amount)
	if(!isnull(get_charge()))
		cell.give(amount)
		return 1
	return 0

/obj/mecha/allow_drop()
	return 0


//////////////////////////////////////// Action Buttons ///////////////////////////////////////////////

/obj/mecha/proc/GrantActions(var/mob/living/user, var/human_occupant = 0)
	if(human_occupant)
		eject_action.chassis = src
		eject_action.Grant(user)

	internals_action.chassis = src
	internals_action.Grant(user)

	cycle_action.chassis = src
	cycle_action.Grant(user)

	lights_action.chassis = src
	lights_action.Grant(user)

	stats_action.chassis = src
	stats_action.Grant(user)


/obj/mecha/proc/RemoveActions(var/mob/living/user, var/human_occupant = 0)
	if(human_occupant)
		eject_action.Remove(user)
	internals_action.Remove(user)
	cycle_action.Remove(user)
	lights_action.Remove(user)
	stats_action.Remove(user)


/datum/action/mecha
	check_flags = AB_CHECK_RESTRAINED | AB_CHECK_STUNNED | AB_CHECK_ALIVE
	action_type = AB_INNATE
	var/obj/mecha/chassis


/datum/action/mecha/mech_eject
	name = "Eject From Mech"
	button_icon_state = "mech_eject"

/datum/action/mecha/mech_eject/Activate()
	if(!owner || !iscarbon(owner))
		return
	if(!chassis || chassis.occupant != owner)
		return
	chassis.go_out()


/datum/action/mecha/mech_toggle_internals
	name = "Toggle Internal Airtank Usage"
	button_icon_state = "mech_toggle_internals"

/datum/action/mecha/mech_toggle_internals/Activate()
	if(!owner || !chassis || chassis.occupant != owner)
		return
	chassis.use_internal_tank = !chassis.use_internal_tank
	if(chassis.use_internal_tank)
		button_icon_state = "mech_toggle_internals_on"
	else
		button_icon_state = "mech_toggle_internals"
	chassis.occupant_message("Now taking air from [chassis.use_internal_tank?"internal airtank":"environment"].")
	chassis.log_message("Now taking air from [chassis.use_internal_tank?"internal airtank":"environment"].")


/datum/action/mecha/mech_cycle_equip
	name = "Cycle Equipment"
	button_icon_state = "mech_cycle_equip"

/datum/action/mecha/mech_cycle_equip/Activate()
	if(!owner || !chassis || chassis.occupant != owner)
		return
	if(chassis.equipment.len == 0)
		chassis.occupant_message("No equipment available.")
		return
	if(!chassis.selected)
		chassis.selected = chassis.equipment[1]
		chassis.occupant_message("You select [chassis.selected]")
		send_byjax(chassis.occupant,"exosuit.browser","eq_list",chassis.get_equipment_list())
		return
	var/number = 0
	for(var/A in chassis.equipment)
		number++
		if(A == chassis.selected)
			if(chassis.equipment.len == number)
				chassis.selected = null
				chassis.occupant_message("You switch to no equipment")
			else
				chassis.selected = chassis.equipment[number+1]
				chassis.occupant_message("You switch to [chassis.selected]")
			send_byjax(chassis.occupant,"exosuit.browser","eq_list",chassis.get_equipment_list())
			return


/datum/action/mecha/mech_toggle_lights
	name = "Toggle Lights"
	button_icon_state = "mech_toggle_lights"

/datum/action/mecha/mech_toggle_lights/Activate()
	if(!owner || !chassis || chassis.occupant != owner)
		return
	chassis.lights = !chassis.lights
	if(chassis.lights)
		chassis.AddLuminosity(chassis.lights_power)
		button_icon_state = "mech_toggle_lights_on"
	else
		chassis.AddLuminosity(-chassis.lights_power)
		button_icon_state = "mech_toggle_lights"
	chassis.occupant_message("Toggled lights [chassis.lights?"on":"off"].")
	chassis.log_message("Toggled lights [chassis.lights?"on":"off"].")


/datum/action/mecha/mech_view_stats
	name = "View Stats"
	button_icon_state = "mech_view_stats"

/datum/action/mecha/mech_view_stats/Activate()
	if(!owner || !chassis || chassis.occupant != owner)
		return
	chassis.occupant << browse(chassis.get_stats_html(), "window=exosuit")
