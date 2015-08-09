#define MAX_ADMIN_BANS_PER_ADMIN 1

//Either pass the mob you wish to ban in the 'banned_mob' attribute, or the banckey, banip and bancid variables. If both are passed, the mob takes priority! If a mob is not passed, banckey is the minimum that needs to be passed! banip and bancid are optional.
/datum/admins/proc/DB_ban_record(bantype, mob/banned_mob, duration = -1, reason, job = "", rounds = 0, banckey = null, banip = null, bancid = null)

	if(!check_rights(R_BAN))	return

	establish_db_connection()
	if(!dbcon.IsConnected())
		return

	var/serverip = "[world.internet_address]:[world.port]"
	var/bantype_pass = 0
	var/bantype_str
	var/maxadminbancheck	//Used to limit the number of active bans of a certein type that each admin can give. Used to protect against abuse or mutiny.
	var/announceinirc		//When set, it announces the ban in irc. Intended to be a way to raise an alarm, so to speak.
	var/blockselfban		//Used to prevent the banning of yourself.
	var/kickbannedckey		//Defines whether this proc should kick the banned person, if they are connected (if banned_mob is defined).
							//some ban types kick players after this proc passes (tempban, permaban), but some are specific to db_ban, so
							//they should kick within this proc.
	switch(bantype)
		if(BANTYPE_PERMA)
			bantype_str = "PERMABAN"
			duration = -1
			bantype_pass = 1
			blockselfban = 1
		if(BANTYPE_TEMP)
			bantype_str = "TEMPBAN"
			bantype_pass = 1
			blockselfban = 1
		if(BANTYPE_JOB_PERMA)
			bantype_str = "JOB_PERMABAN"
			duration = -1
			bantype_pass = 1
		if(BANTYPE_JOB_TEMP)
			bantype_str = "JOB_TEMPBAN"
			bantype_pass = 1
		if(BANTYPE_APPEARANCE)
			bantype_str = "APPEARANCE_PERMABAN"
			duration = -1
			bantype_pass = 1
		if(BANTYPE_ADMIN_PERMA)
			bantype_str = "ADMIN_PERMABAN"
			duration = -1
			bantype_pass = 1
			maxadminbancheck = 1
			announceinirc = 1
			blockselfban = 1
			kickbannedckey = 1
		if(BANTYPE_ADMIN_TEMP)
			bantype_str = "ADMIN_TEMPBAN"
			bantype_pass = 1
			maxadminbancheck = 1
			announceinirc = 1
			blockselfban = 1
			kickbannedckey = 1
	if( !bantype_pass ) return
	if( !istext(reason) ) return
	if( !isnum(duration) ) return

	var/ckey
	var/computerid
	var/ip

	if(ismob(banned_mob))
		ckey = banned_mob.ckey
		if(banned_mob.client)
			computerid = banned_mob.client.computer_id
			ip = banned_mob.client.address
		else
			computerid = banned_mob.computer_id
			ip = banned_mob.lastKnownIP
	else if(banckey)
		ckey = ckey(banckey)
		computerid = bancid
		ip = banip

	var/DBQuery/query = dbcon.NewQuery("Selecciona la ID desde [format_table_name("player")] donde ckey = '[ckey]'")
	query.Execute()
	var/validckey = 0
	if(query.NextRow())
		validckey = 1
	if(!validckey)
		if(!banned_mob || (banned_mob && !IsGuestKey(banned_mob.key)))
			message_admins("<font color='red'>[key_name_admin(usr)] Intento banear a [ckey], pero [ckey] no esta conectado todavia. por favor banea a los usuarios que esten online.</font>",1)
			return

	var/a_ckey
	var/a_computerid
	var/a_ip

	if(src.owner && istype(src.owner, /client))
		a_ckey = src.owner:ckey
		a_computerid = src.owner:computer_id
		a_ip = src.owner:address

	if(blockselfban)
		if(a_ckey == ckey)
			usr << "<span class='danger'>No puedes banearte a ti mismo.</span>"
			return

	var/who
	for(var/client/C in clients)
		if(!who)
			who = "[C]"
		else
			who += ", [C]"

	var/adminwho
	for(var/client/C in admins)
		if(!adminwho)
			adminwho = "[C]"
		else
			adminwho += ", [C]"

	reason = sanitizeSQL(reason)

	if(maxadminbancheck)
		var/DBQuery/adm_query = dbcon.NewQuery("Selecciona una (id) como numero desde [format_table_name("ban")] donde (a_ckey = '[a_ckey]') y (bantype = 'ADMIN_PERMABAN'  o (bantype = 'ADMIN_TEMPBAN' y expiration_time > Ahora())) y isnull(unbanned)")
		adm_query.Execute()
		if(adm_query.NextRow())
			var/adm_bans = text2num(adm_query.item[1])
			if(adm_bans >= MAX_ADMIN_BANS_PER_ADMIN)
				usr << "<span class='danger'>Acabas de registrar [MAX_ADMIN_BANS_PER_ADMIN] baneos o mas. ¡No abuses!</span>"
				return

	var/sql = "INSERT INTO [format_table_name("ban")] (`id`,`bantime`,`serverip`,`bantype`,`reason`,`job`,`duration`,`rounds`,`expiration_time`,`ckey`,`computerid`,`ip`,`a_ckey`,`a_computerid`,`a_ip`,`who`,`adminwho`,`edits`,`unbanned`,`unbanned_datetime`,`unbanned_ckey`,`unbanned_computerid`,`unbanned_ip`) VALUES (null, Now(), '[serverip]', '[bantype_str]', '[reason]', '[job]', [(duration)?"[duration]":"0"], [(rounds)?"[rounds]":"0"], Now() + INTERVAL [(duration>0) ? duration : 0] MINUTE, '[ckey]', '[computerid]', '[ip]', '[a_ckey]', '[a_computerid]', '[a_ip]', '[who]', '[adminwho]', '', null, null, null, null, null)"
	var/DBQuery/query_insert = dbcon.NewQuery(sql)
	query_insert.Execute()
			usr << "<span class='adminnotice'>Ban guardado en la base de datos.</span>"
	message_admins("[key_name_admin(usr)] Ha sido añadido a [bantype_str] por [ckey] [(job)?"([job])":""] [(duration > 0)?"([duration] minutes)":""] con la razon: \"[reason]\" A la base de datos de ban.",1)

	if(announceinirc)
		send2irc("BAN ALERT","[a_ckey] aplico una [bantype_str] en [ckey]")

	if(kickbannedckey)
		if(banned_mob && banned_mob.client && banned_mob.client.ckey == banckey)
			del(banned_mob.client)


/datum/admins/proc/DB_ban_unban(ckey, bantype, job = "")

	if(!check_rights(R_BAN))	return

	var/bantype_str
	if(bantype)
		var/bantype_pass = 0
		switch(bantype)
			if(BANTYPE_PERMA)
				bantype_str = "PERMABAN"
				bantype_pass = 1
			if(BANTYPE_TEMP)
				bantype_str = "TEMPBAN"
				bantype_pass = 1
			if(BANTYPE_JOB_PERMA)
				bantype_str = "JOB_PERMABAN"
				bantype_pass = 1
			if(BANTYPE_JOB_TEMP)
				bantype_str = "JOB_TEMPBAN"
				bantype_pass = 1
			if(BANTYPE_APPEARANCE)
				bantype_str = "APPEARANCE_PERMABAN"
				bantype_pass = 1
			if(BANTYPE_ADMIN_PERMA)
				bantype_str = "ADMIN_PERMABAN"
				bantype_pass = 1
			if(BANTYPE_ADMIN_TEMP)
				bantype_str = "ADMIN_TEMPBAN"
				bantype_pass = 1
			if(BANTYPE_ANY_FULLBAN)
				bantype_str = "ANY"
				bantype_pass = 1
		if( !bantype_pass ) return

	var/bantype_sql
	if(bantype_str == "ANY")
		bantype_sql = "(bantype = 'PERMABAN' o (bantype = 'TEMPBAN' y expiration_time > Ahora() ) )"
	else
		bantype_sql = "bantype = '[bantype_str]'"

	var/sql = "Selecciona ID desde [format_table_name("ban")] donde ckey = '[ckey]' y [bantype_sql] y (unbanned is null OR unbanned = false)"
	if(job)
		sql += " AND job = '[job]'"

	establish_db_connection()
	if(!dbcon.IsConnected())
		return

	var/ban_id
	var/ban_number = 0 //failsafe

	var/DBQuery/query = dbcon.NewQuery(sql)
	query.Execute()
	while(query.NextRow())
		ban_id = query.item[1]
		ban_number++;

	if(ban_number == 0)
		usr << "<span class='danger'>La actualizacion de la base de datos ha fallado debido a que no hay Ban que cumplan los criterios de busqueda. contacte con el administrador de la base de datos.</span>"
		return

	if(ban_number > 1)
		usr << "<span class='danger'>La actualizacion de la base de datos ha fallado debido a que no hay Bans que cumplan los criterios de busqueda. Anota la  ckey, trabajo y el tiempo y contacte con el administrador de la base de datos.</span>"
		return

	if(istext(ban_id))
		ban_id = text2num(ban_id)
	if(!isnum(ban_id))
		usr << "<span class='danger'>La actualizacion de la base de datos ha fallado debido a un error en la ID del Ban. Contacte con el administrador de la base de datos.</span>"
		return

	DB_ban_unban_by_id(ban_id)

/datum/admins/proc/DB_ban_edit(banid = null, param = null)

	if(!check_rights(R_BAN))	return

	if(!isnum(banid) || !istext(param))
		usr << "Cancelled"
		return

	var/DBQuery/query = dbcon.NewQuery("Selecciona ckey, duracion, razon desde [format_table_name("ban")] Donde ID = [banid]")
	query.Execute()

	var/eckey = usr.ckey	//Editing admin ckey
	var/pckey				//(banned) Player ckey
	var/duration			//Old duration
	var/reason				//Old reason

	if(query.NextRow())
		pckey = query.item[1]
		duration = query.item[2]
		reason = query.item[3]
	else
		usr << "ID invalida. Contacta al administrador de la base de datos."
		return

	reason = sanitizeSQL(reason)
	var/value

	switch(param)
		if("reason")
			if(!value)
				value = input("Inserta la razon [pckey]'s ban", "Nueva razon", "[reason]", null) as null|text
				value = sanitizeSQL(value)
				if(!value)
					usr << "Cancelado."
					return

			var/DBQuery/update_query = dbcon.NewQuery("Actualiza [format_table_name("ban")] escribe una razon = '[value]', edits = CONCAT(edits,'- [eckey] Cambio la razon del ban por <cite><b>\\\"[reason]\\\"</b></cite> to <cite><b>\\\"[value]\\\"</b></cite><BR>') donde ID = [banid]")
			update_query.Execute()
			message_admins("[key_name_admin(usr)] Ha editado un ban por [pckey]'s razon desde [reason] a [value]",1)
		if("duration")
			if(!value)
				value = input("Inserta la nueva duracion (en minutos) para [pckey]'s ban", "Nueva duracion", "[duration]", null) as null|num
				if(!isnum(value) || !value)
					usr << "Cancelado."
					return

			var/DBQuery/update_query = dbcon.NewQuery("Actualiza [format_table_name("ban")] escribe duracion = [value], edits = CONCAT(edits,'- [eckey] Cambio la duracion del ban desde [duration] a [value]<br>'), expiration_time = DATE_ADD(bantime, INTERVAL [value] MINUTE) donde ID = [banid]")
			message_admins("[key_name_admin(usr)] Ha editado un ban [pckey]'s duracion desde [duration] a [value]",1)
			update_query.Execute()
		if("unban")
			if(alert("Desbanear [pckey]?", "Desbanear?", "Si", "No") == "Yes")
				DB_ban_unban_by_id(banid)
				return
			else
				usr << "Cancelado"
				return
		else
			usr << "Cancelado"
			return

/datum/admins/proc/DB_ban_unban_by_id(id)

	if(!check_rights(R_BAN))	return

	var/sql = "Selecciona ckey desde [format_table_name("ban")] donde ID = [id]"

	establish_db_connection()
	if(!dbcon.IsConnected())
		return

	var/ban_number = 0 //failsafe

	var/pckey
	var/DBQuery/query = dbcon.NewQuery(sql)
	query.Execute()
	while(query.NextRow())
		pckey = query.item[1]
		ban_number++;

	if(ban_number == 0)
		usr << "<span class='danger'>Actualizacion de la base de datos ha fallado debido a que esa ID no existe en la base de datos.</span>"
		return

	if(ban_number > 1)
		usr << "<span class='danger'>Actualizacion de la base de datos ha fallado debido a que multiples ban tienen el mismo ID. Contacta al administrador de la base de datos.</span>"
		return

	if(!src.owner || !istype(src.owner, /client))
		return

	var/unban_ckey = src.owner:ckey
	var/unban_computerid = src.owner:computer_id
	var/unban_ip = src.owner:address

	var/sql_update = "Actualiza [format_table_name("ban")] SET unbanned = 1, unbanned_datetime = Now(), unbanned_ckey = '[unban_ckey]', unbanned_computerid = '[unban_computerid]', unbanned_ip = '[unban_ip]' donde ID = [id]"
	message_admins("[key_name_admin(usr)] ha quitado [pckey]'s ban.",1)

	var/DBQuery/query_update = dbcon.NewQuery(sql_update)
	query_update.Execute()


/client/proc/DB_ban_panel()
	set category = "Admin"
	set name = "Panel de baneos"
	set desc = "Editar permisos de administrador"

	if(!holder)
		return

	holder.DB_ban_panel()


/datum/admins/proc/DB_ban_panel(playerckey = null, adminckey = null)
	if(!usr.client)
		return

	if(!check_rights(R_BAN))	return

	establish_db_connection()
	if(!dbcon.IsConnected())
		usr << "<span class='danger'Fallo al conectar con la base de datos.</span>"
		return

	var/output = "<div align='center'><table width='90%'><tr>"

	output += "<td width='35%' align='center'>"
	output += "<h1>Panel de baneos</h1>"
	output += "</td>"

	output += "<td width='65%' align='center' bgcolor='#f9f9f9'>"

	output += "<form method='GET' action='?src=\ref[src]'><b>Añadir ban personalizado:</b> (Usalo SOLO cuando no puedas banear de otra forma.)"
	output += "<input type='hidden' name='src' value='\ref[src]'>"
	output += "<table width='100%'><tr>"
	output += "<td><b>Ban type:</b><select name='dbbanaddtype'>"
	output += "<option value=''>--</option>"
	output += "<option value='[BANTYPE_PERMA]'>PERMABAN</option>"
	output += "<option value='[BANTYPE_TEMP]'>TEMPBAN</option>"
	output += "<option value='[BANTYPE_JOB_PERMA]'>JOB PERMABAN</option>"
	output += "<option value='[BANTYPE_JOB_TEMP]'>JOB TEMPBAN</option>"
	output += "<option value='[BANTYPE_APPEARANCE]'>IDENTITY BAN</option>"
	output += "<option value='[BANTYPE_ADMIN_PERMA]'>ADMIN PERMABAN</option>"
	output += "<option value='[BANTYPE_ADMIN_TEMP]'>ADMIN TEMPBAN</option>"
	output += "</select></td>"
	output += "<td><b>Ckey:</b> <input type='text' name='dbbanaddckey'></td></tr>"
	output += "<tr><td><b>IP:</b> <input type='text' name='dbbanaddip'></td>"
	output += "<td><b>Computer id:</b> <input type='text' name='dbbanaddcid'></td></tr>"
	output += "<tr><td><b>Duration:</b> <input type='text' name='dbbaddduration'></td>"
	output += "<td><b>Job:</b><select name='dbbanaddjob'>"
	output += "<option value=''>--</option>"
	for(var/j in get_all_jobs())
		output += "<option value='[j]'>[j]</option>"
	for(var/j in nonhuman_positions)
		output += "<option value='[j]'>[j]</option>"
	for(var/j in list("traitor","changeling","operative","revolutionary", "gangster","cultist","wizard"))
		output += "<option value='[j]'>[j]</option>"
	output += "</select></td></tr></table>"
	output += "<b>Reason:<br></b><textarea name='dbbanreason' cols='50'></textarea><br>"
	output += "<input type='submit' value='Add ban'>"
	output += "</form>"

	output += "</td>"
	output += "</tr>"
	output += "</table>"

	output += "<form method='GET' action='?src=\ref[src]'><b>Search:</b> "
	output += "<input type='hidden' name='src' value='\ref[src]'>"
	output += "<b>Ckey:</b> <input type='text' name='dbsearchckey' value='[playerckey]'>"
	output += "<b>Admin ckey:</b> <input type='text' name='dbsearchadmin' value='[adminckey]'>"
	output += "<input type='submit' value='search'>"
	output += "</form>"
	output += "Por favor anota todos los jobbans, bans o desbans que se han hecho en la ultima ronda."

	if(adminckey || playerckey)

		var/blcolor = "#ffeeee" //banned light
		var/bdcolor = "#ffdddd" //banned dark
		var/ulcolor = "#eeffee" //unbanned light
		var/udcolor = "#ddffdd" //unbanned dark

		output += "<table width='90%' bgcolor='#e3e3e3' cellpadding='5' cellspacing='0' align='center'>"
		output += "<tr>"
		output += "<th width='25%'><b>TYPE</b></th>"
		output += "<th width='20%'><b>CKEY</b></th>"
		output += "<th width='20%'><b>TIME APPLIED</b></th>"
		output += "<th width='20%'><b>ADMIN</b></th>"
		output += "<th width='15%'><b>OPTIONS</b></th>"
		output += "</tr>"

		adminckey = ckey(adminckey)
		playerckey = ckey(playerckey)
		var/adminsearch = ""
		var/playersearch = ""
		if(adminckey)
			adminsearch = "AND a_ckey = '[adminckey]' "
		if(playerckey)
			playersearch = "AND ckey = '[playerckey]' "

		var/DBQuery/select_query = dbcon.NewQuery("SELECT id, bantime, bantype, reason, job, duration, expiration_time, ckey, a_ckey, unbanned, unbanned_ckey, unbanned_datetime, edits FROM [format_table_name("ban")] WHERE 1 [playersearch] [adminsearch] ORDER BY bantime DESC")
		select_query.Execute()

		while(select_query.NextRow())
			var/banid = select_query.item[1]
			var/bantime = select_query.item[2]
			var/bantype  = select_query.item[3]
			var/reason = select_query.item[4]
			var/job = select_query.item[5]
			var/duration = select_query.item[6]
			var/expiration = select_query.item[7]
			var/ckey = select_query.item[8]
			var/ackey = select_query.item[9]
			var/unbanned = select_query.item[10]
			var/unbanckey = select_query.item[11]
			var/unbantime = select_query.item[12]
			var/edits = select_query.item[13]

			var/lcolor = blcolor
			var/dcolor = bdcolor
			if(unbanned)
				lcolor = ulcolor
				dcolor = udcolor

			var/typedesc =""
			switch(bantype)
				if("PERMABAN")
					typedesc = "<font color='red'><b>PERMABAN</b></font>"
				if("TEMPBAN")
					typedesc = "<b>TEMPBAN</b><br><font size='2'>([duration] minutos [(unbanned) ? "" : "(<a href=\"byond://?src=\ref[src];dbbanedit=duration;dbbanid=[banid]\">Edit</a>))"]<br>Expires [expiration]</font>"
				if("JOB_PERMABAN")
					typedesc = "<b>JOBBAN</b><br><font size='2'>([job])"
				if("JOB_TEMPBAN")
					typedesc = "<b>TEMP JOBBAN</b><br><font size='2'>([job])<br>([duration] minutos<br>Expires [expiration]"
				if("APPEARANCE_PERMABAN")
					typedesc = "<b>IDENTITY PERMABAN</b>"
				if("ADMIN_PERMABAN")
					typedesc = "<b>ADMIN PERMABAN</b>"
				if("ADMIN_TEMPBAN")
					typedesc = "<b>ADMIN TEMPBAN</b><br><font size='2'>([duration] minutos [(unbanned) ? "" : "(<a href=\"byond://?src=\ref[src];dbbanedit=duration;dbbanid=[banid]\">Edit</a>))"]<br>Expires [expiration]</font>"

			output += "<tr bgcolor='[dcolor]'>"
			output += "<td align='center'>[typedesc]</td>"
			output += "<td align='center'><b>[ckey]</b></td>"
			output += "<td align='center'>[bantime]</td>"
			output += "<td align='center'><b>[ackey]</b></td>"
			output += "<td align='center'>[(unbanned) ? "" : "<b><a href=\"byond://?src=\ref[src];dbbanedit=unban;dbbanid=[banid]\">Unban</a></b>"]</td>"
			output += "</tr>"
			output += "<tr bgcolor='[lcolor]'>"
			output += "<td align='center' colspan='5'><b>Razon: [(unbanned) ? "" : "(<a href=\"byond://?src=\ref[src];dbbanedit=reason;dbbanid=[banid]\">Edit</a>)"]</b> <cite>\"[reason]\"</cite></td>"
			output += "</tr>"
			if(edits)
				output += "<tr bgcolor='[dcolor]'>"
				output += "<td align='center' colspan='5'><b>EDITS</b></td>"
				output += "</tr>"
				output += "<tr bgcolor='[lcolor]'>"
				output += "<td align='center' colspan='5'><font size='2'>[edits]</font></td>"
				output += "</tr>"
			if(unbanned)
				output += "<tr bgcolor='[dcolor]'>"
				output += "<td align='center' colspan='5' bgcolor=''><b>Desbaneado por el admin [unbanckey] en [unbantime]</b></td>"
				output += "</tr>"
			output += "<tr>"
			output += "<td colspan='5' bgcolor='white'>&nbsp</td>"
			output += "</tr>"

		output += "</table></div>"

	usr << browse(output,"window=lookupbans;size=900x500")
