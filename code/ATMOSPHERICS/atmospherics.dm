/*
Quick overview:

Pipes combine to form pipelines
Pipelines and other atmospheric objects combine to form pipe_networks
	Note: A single pipe_network represents a completely open space

Pipes -> Pipelines
Pipelines + Other Objects -> Pipe network

*/

/obj/machinery/atmospherics
	anchored = 1
	idle_power_usage = 0
	active_power_usage = 0
	power_channel = ENVIRON
	var/nodealert = 0
	var/can_unwrench = 0
	var/initialize_directions = 0
	var/pipe_color
	var/obj/item/pipe/stored
	var/global/list/iconsetids = list()
	var/global/list/pipeimages = list()

	var/image/pipe_vision_img = null

/obj/machinery/atmospherics/New()
	..()
	SSair.atmos_machinery += src
	SetInitDirections()
	if(can_unwrench)
		stored = new(src, make_from=src)

/obj/machinery/atmospherics/Destroy()
	SSair.atmos_machinery -= src
	if (stored)
		qdel(stored)
	stored = null

	for(var/mob/living/L in src)
		L.remove_ventcrawl()
		L.forceMove(get_turf(src))
	if(pipe_vision_img)
		qdel(pipe_vision_img)

	..()

//this is called just after the air controller sets up turfs
/obj/machinery/atmospherics/proc/atmosinit()
	return

/obj/machinery/atmospherics/proc/SetInitDirections()
	return

/obj/machinery/atmospherics/proc/returnPipenet()
	return

/obj/machinery/atmospherics/proc/returnPipenetAir()
	return

/obj/machinery/atmospherics/proc/setPipenet()
	return

/obj/machinery/atmospherics/proc/replacePipenet()
	return

/obj/machinery/atmospherics/proc/build_network()
	// Called to build a network from this node
	return

/obj/machinery/atmospherics/proc/disconnect(obj/machinery/atmospherics/reference)
	return

/obj/machinery/atmospherics/update_icon()
	return

/obj/machinery/atmospherics/attackby(obj/item/weapon/W, mob/user, params)
	if(can_unwrench && istype(W, /obj/item/weapon/wrench))
		var/turf/T = get_turf(src)
		if (level==1 && isturf(T) && T.intact)
			user << "<span class='warning'>You must remove the plating first!</span>"
			return 1
		var/datum/gas_mixture/int_air = return_air()
		var/datum/gas_mixture/env_air = loc.return_air()
		add_fingerprint(user)

		var/unsafe_wrenching = FALSE
		var/internal_pressure = int_air.return_pressure()-env_air.return_pressure()

		playsound(src.loc, 'sound/items/Ratchet.ogg', 50, 1)
		user << "<span class='notice'>You begin to unfasten \the [src]...</span>"
		if (internal_pressure > 2*ONE_ATMOSPHERE)
			user << "<span class='warning'>As you begin unwrenching \the [src] a gush of air blows in your face... maybe you should reconsider?</span>"
			unsafe_wrenching = TRUE //Oh dear oh dear

		if (do_after(user, 20, target = src) && !gc_destroyed)
			user.visible_message( \
				"[user] unfastens \the [src].", \
				"<span class='notice'>You unfasten \the [src].</span>", \
				"<span class='italics'>You hear ratchet.</span>")
			investigate_log("was <span class='warning'>REMOVED</span> by [key_name(usr)]", "atmos")

			//You unwrenched a pipe full of pressure? let's splat you into the wall silly.
			if(unsafe_wrenching)
				unsafe_pressure_release(user,internal_pressure)
			Deconstruct()

	else
		return ..()


//Called when an atmospherics object is unwrenched while having a large pressure difference
//with it's locs air contents.
/obj/machinery/atmospherics/proc/unsafe_pressure_release(mob/user,pressures)
	if(!user)
		return

	if(!pressures)
		var/datum/gas_mixture/int_air = return_air()
		var/datum/gas_mixture/env_air = loc.return_air()
		pressures = int_air.return_pressure()-env_air.return_pressure()

	var/fuck_you_dir = get_dir(src,user)
	var/turf/general_direction = get_edge_target_turf(user,fuck_you_dir)
	user.visible_message("<span class='danger'>[user] is sent flying by pressure!</span>","<span class='userdanger'>The pressure sends you flying!</span>")
	//Values based on 2*ONE_ATMOS (the unsafe pressure), resulting in 20 range and 4 speed
	user.throw_at(general_direction,pressures/10,pressures/50)

/obj/machinery/atmospherics/Deconstruct()
	if(can_unwrench)
		var/turf/T = loc
		stored.loc = T
		transfer_fingerprints_to(stored)
		stored = null

	qdel(src)

/obj/machinery/atmospherics/proc/nullifyPipenet(datum/pipeline/P)
	P.other_atmosmch -= src

/obj/machinery/atmospherics/proc/getpipeimage(iconset, iconstate, direction, col=rgb(255,255,255))

	//Add identifiers for the iconset
	if(iconsetids[iconset] == null)
		iconsetids[iconset] = num2text(iconsetids.len + 1)

	//Generate a unique identifier for this image combination
	var/identifier = iconsetids[iconset] + "_[iconstate]_[direction]_[col]"

	var/image/img
	if(pipeimages[identifier] == null)
		img = image(iconset, icon_state=iconstate, dir=direction)
		img.color = col

		pipeimages[identifier] = img

	else
		img = pipeimages[identifier]

	return img

/obj/machinery/atmospherics/construction(D, P, pipe_type, obj_color)
	dir = D
	initialize_directions = P
	if(can_unwrench)
		color = obj_color
		pipe_color = obj_color
		stored.dir = D				  //need to define them here, because the obj directions...
		stored.pipe_type = pipe_type  //... were not set at the time the stored pipe was created
		stored.color = obj_color
	var/turf/T = loc
	level = T.intact ? 2 : 1
	atmosinit()
	var/list/nodes = pipeline_expansion()
	for(var/obj/machinery/atmospherics/A in nodes)
		A.atmosinit()
		A.addMember(src)
	build_network()

/obj/machinery/atmospherics/singularity_pull(S, current_size)
	if(current_size >= STAGE_FIVE)
		Deconstruct()


//Find a connecting /obj/machinery/atmospherics in specified direction
/obj/machinery/atmospherics/proc/findConnecting(direction)
	for(var/obj/machinery/atmospherics/target in get_step(src, direction))
		if(target.initialize_directions & get_dir(target,src))
			return target


#define VENT_SOUND_DELAY 30

/obj/machinery/atmospherics/relaymove(mob/living/user, direction)
	if(!(direction & initialize_directions)) //cant go this way.
		return

	var/obj/machinery/atmospherics/target_move = findConnecting(direction)
	if(target_move)
		if(is_type_in_list(target_move, ventcrawl_machinery) && target_move.can_crawl_through())
			user.remove_ventcrawl()
			user.forceMove(target_move.loc) //handle entering and so on.
			user.visible_message("<span class='notice'>You hear something squeezing through the ducts...</span>","<span class='notice'>You climb out the ventilation system.")
		else if(target_move.can_crawl_through())
			if(returnPipenet() != target_move.returnPipenet())
				user.update_pipe_vision(target_move)
			user.loc = target_move
			user.client.eye = target_move  //Byond only updates the eye every tick, This smooths out the movement
			if(world.time - user.last_played_vent > VENT_SOUND_DELAY)
				user.last_played_vent = world.time
				playsound(src, 'sound/machines/ventcrawl.ogg', 50, 1, -3)
	else
		if((direction & initialize_directions) || is_type_in_list(src, ventcrawl_machinery) && can_crawl_through()) //if we move in a way the pipe can connect, but doesn't - or we're in a vent
			user.remove_ventcrawl()
			user.forceMove(src.loc)
			user.visible_message("<span class='notice'>You hear something squeezing through the ducts...</span>","<span class='notice'>You climb out the ventilation system.")
	user.canmove = 0
	spawn(1)
		user.canmove = 1


/obj/machinery/atmospherics/AltClick(mob/living/L)
	if(is_type_in_list(src, ventcrawl_machinery))
		L.handle_ventcrawl(src)
		return
	..()


/obj/machinery/atmospherics/proc/can_crawl_through()
	return 1