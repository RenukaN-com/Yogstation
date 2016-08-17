/datum/computer_file/program/card_mod
	filename = "cardmod"
	filedesc = "ID card modification program"
	program_icon_state = "id"
	extended_desc = "Program for programming employee ID cards to access parts of the station."
	transfer_access = access_change_ids
	requires_ntnet = 0
	size = 8
	var/mod_mode = 1
	var/is_centcom = 0
	var/show_assignments = 0
	var/minor = 0
	var/authenticated = 0
	var/list/reg_ids = list()
	var/list/region_access = null
	var/list/head_subordinates = null
	var/target_dept = 0 //Which department this computer has access to. 0=all departments
	var/change_position_cooldown = 60
	//Jobs you cannot open new positions for
	var/list/blacklisted = list(
		"AI",
		"Assistant",
		"Cyborg",
		"Captain",
		"Head of Personnel",
		"Head of Security",
		"Chief Engineer",
		"Research Director",
		"Chief Medical Officer",
		"Chaplain")

	//The scaling factor of max total positions in relation to the total amount of people on board the station in %
	var/max_relative_positions = 30 //30%: Seems reasonable, limit of 6 @ 20 players

	//This is used to keep track of opened positions for jobs to allow instant closing
	//Assoc array: "JobName" = (int)<Opened Positions>
	var/list/opened_positions = list();


/datum/computer_file/program/card_mod/event_idremoved(background, slot)
	if(slot == 2)
		minor = 0
		authenticated = 0
		head_subordinates = null
		region_access = null


/datum/computer_file/program/card_mod/proc/job_blacklisted(jobtitle)
	return (jobtitle in blacklisted)


//Logic check for if you can open the job
/datum/computer_file/program/card_mod/proc/can_open_job(datum/job/job)
	if(job)
		if(!job_blacklisted(job.title))
			if((job.total_positions <= player_list.len * (max_relative_positions / 100)))
				var/delta = (world.time / 10) - time_last_changed_position
				if((change_position_cooldown < delta) || (opened_positions[job.title] < 0))
					return 1
				return -2
			return 0
	return 0

//Logic check for if you can close the job
/datum/computer_file/program/card_mod/proc/can_close_job(datum/job/job)
	if(job)
		if(!job_blacklisted(job.title))
			if(job.total_positions > job.current_positions)
				var/delta = (world.time / 10) - time_last_changed_position
				if((change_position_cooldown < delta) || (opened_positions[job.title] > 0))
					return 1
				return -2
			return 0
	return 0


/datum/computer_file/program/card_mod/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = 0, datum/tgui/master_ui = null, datum/ui_state/state = default_state)

	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if (!ui)

		var/datum/asset/assets = get_asset_datum(/datum/asset/simple/headers)
		assets.send(user)

		ui = new(user, src, ui_key, "identification_computer", "ID card modification program", 600, 700, state = state)
		ui.open()
		ui.set_autoupdate(state = 1)


/datum/computer_file/program/card_mod/proc/format_jobs(list/jobs)
	var/obj/item/weapon/card/id/id_card = computer.card_slot.stored_card
	var/list/formatted = list()
	for(var/job in jobs)
		formatted.Add(list(list(
			"display_name" = replacetext(job, "&nbsp", " "),
			"target_rank" = id_card && id_card.assignment ? id_card.assignment : "Unassigned",
			"job" = job)))

	return formatted

/datum/computer_file/program/card_mod/ui_act(action, params)
	if(..())
		return 1

	var/obj/item/weapon/card/id/user_id_card = null
	var/mob/user = usr

	var/obj/item/weapon/card/id/id_card = computer.card_slot.stored_card
	var/obj/item/weapon/card/id/auth_card = computer.card_slot.stored_card2

	if(auth_card)
		user_id_card = auth_card
	else
		if(ishuman(user))
			var/mob/living/carbon/human/h = user
			user_id_card = h.get_idcard()

	switch(action)
		if("PRG_switchm")
			if(params["target"] == "mod")
				mod_mode = 1
			else if (params["target"] == "manifest")
				mod_mode = 0
			else if (params["target"] == "manage")
				mod_mode = 2
		if("PRG_togglea")
			if(show_assignments)
				show_assignments = 0
			else
				show_assignments = 1
		if("PRG_print")
			if(computer && computer.nano_printer) //This option should never be called if there is no printer
				if(mod_mode)
					if(authorized())
						var/contents = {"<h4>Access Report</h4>
									<u>Prepared By:</u> [user_id_card && user_id_card.registered_name ? user_id_card.registered_name : "Unknown"]<br>
									<u>For:</u> [id_card.registered_name ? id_card.registered_name : "Unregistered"]<br>
									<hr>
									<u>Assignment:</u> [id_card.assignment]<br>
									<u>Access:</u><br>
								"}

						var/known_access_rights = get_all_accesses()
						for(var/A in id_card.access)
							if(A in known_access_rights)
								contents += "  [get_access_desc(A)]"

						if(!computer.nano_printer.print_text(contents,"access report"))
							usr << "<span class='notice'>Hardware error: Printer was unable to print the file. It may be out of paper.</span>"
							return
						else
							computer.visible_message("<span class='notice'>\The [computer] prints out paper.</span>")
				else
					var/contents = {"<h4>Crew Manifest</h4>
									<br>
									[data_core ? data_core.get_manifest(0) : ""]
									"}
					if(!computer.nano_printer.print_text(contents,text("crew manifest ([])", worldtime2text())))
						usr << "<span class='notice'>Hardware error: Printer was unable to print the file. It may be out of paper.</span>"
						return
					else
						computer.visible_message("<span class='notice'>\The [computer] prints out paper.</span>")
		if("PRG_eject")
			if(computer && computer.card_slot)
				var/select = params["target"]
				switch(select)
					if("id")
						if(id_card)
							data_core.manifest_modify(id_card.registered_name, id_card.assignment)
							computer.proc_eject_id(user, 1)
						else
							var/obj/item/I = usr.get_active_hand()
							if (istype(I, /obj/item/weapon/card/id))
								if(!usr.drop_item())
									return
								I.forceMove(computer)
								computer.card_slot.stored_card = I
					if("auth")
						if(auth_card)
							if(id_card)
								data_core.manifest_modify(id_card.registered_name, id_card.assignment)
							head_subordinates = null
							region_access = null
							authenticated = 0
							minor = 0
							computer.proc_eject_id(user, 2)
						else
							var/obj/item/I = usr.get_active_hand()
							if (istype(I, /obj/item/weapon/card/id))
								if(!usr.drop_item())
									return
								I.forceMove(computer)
								computer.card_slot.stored_card2 = I
		if("PRG_terminate")
			if(computer && ((id_card.assignment in head_subordinates) || id_card.assignment == "Assistant"))
				id_card.assignment = "Unassigned"
				remove_nt_access(id_card)

		if("PRG_edit")
			if(computer && authorized())
				if(params["name"])
					var/temp_name = reject_bad_name(input("Enter name.", "Name", id_card.registered_name))
					if(temp_name)
						id_card.registered_name = temp_name
					else
						computer.visible_message("<span class='notice'>[computer] buzzes rudely.</span>")
				//else if(params["account"])
				//	var/account_num = text2num(input("Enter account number.", "Account", id_card.associated_account_number))
				//	id_card.associated_account_number = account_num
		if("PRG_assign")
			if(computer && authorized() && id_card)
				var/t1 = params["assign_target"]
				if(t1 == "Custom")
					var/temp_t = reject_bad_text(input("Enter a custom job assignment.","Assignment", id_card.assignment), 45)
					//let custom jobs function as an impromptu alt title, mainly for sechuds
					if(temp_t)
						id_card.assignment = temp_t
				else
					var/list/access = list()
					if(is_centcom)
						access = get_centcom_access(t1)
					else
						var/datum/job/jobdatum
						for(var/jobtype in typesof(/datum/job))
							var/datum/job/J = new jobtype
							if(ckey(J.title) == ckey(t1))
								jobdatum = J
								break
						if(!jobdatum)
							usr << "<span class='warning'>No log exists for this job: [t1]</span>"
							return

						access = jobdatum.get_access()

					remove_nt_access(id_card)
					apply_access(id_card, access)
					id_card.assignment = t1

		if("PRG_access")
			if(params["allowed"] && computer && authorized())
				var/access_type = text2num(params["access_target"])
				var/access_allowed = text2num(params["allowed"])
				if(access_type in (is_centcom ? get_all_centcom_access() : get_all_accesses()))
					id_card.access -= access_type
					if(!access_allowed)
						id_card.access += access_type
		if("PRG_open_job")
			var/edit_job_target = params["target"]
			var/datum/job/j = SSjob.GetJob(edit_job_target)
			if(!j)
				return 0
			if(can_open_job(j) != 1)
				return 0
			if(opened_positions[edit_job_target] >= 0)
				time_last_changed_position = world.time / 10
			j.total_positions++
			opened_positions[edit_job_target]++
		if("PRG_close_job")
			var/edit_job_target = params["target"]
			var/datum/job/j = SSjob.GetJob(edit_job_target)
			if(!j)
				return 0
			if(can_close_job(j) != 1)
				return 0
			//Allow instant closing without cooldown if a position has been opened before
			if(opened_positions[edit_job_target] <= 0)
				time_last_changed_position = world.time / 10
			j.total_positions--
			opened_positions[edit_job_target]--
		if("PRG_regsel")
			if(!reg_ids)
				reg_ids = list()
			var/regsel = text2num(params["region"])
			if(regsel in reg_ids)
				reg_ids -= regsel
			else
				reg_ids += regsel

	if(id_card)
		id_card.name = text("[id_card.registered_name]'s ID Card ([id_card.assignment])")

	return 1

/datum/computer_file/program/card_mod/proc/remove_nt_access(obj/item/weapon/card/id/id_card)
	id_card.access -= get_all_accesses()
	id_card.access -= get_all_centcom_access()

/datum/computer_file/program/card_mod/proc/apply_access(obj/item/weapon/card/id/id_card, list/accesses)
	id_card.access |= accesses

/datum/computer_file/program/card_mod/ui_data(mob/user)

	var/list/data = get_header_data()

	data["mmode"] = mod_mode

	var/authed = 0
	if(computer && computer.card_slot)
		var/obj/item/weapon/card/id/auth_card = computer.card_slot.stored_card2
		data["auth_name"] = auth_card ? strip_html_simple(auth_card.name) : "-----"
		authed = authorized()


	if(mod_mode == 2)
		data["slots"] = list()
		var/list/pos = list()
		for(var/datum/job/job in SSjob.occupations)
			if(job.title in blacklisted)
				continue

			var/list/status_open = build_manage(job,1)
			var/list/status_close = build_manage(job,0)

			pos.Add(list(list(
				"title" = job.title,
				"current" = job.current_positions,
				"total" = job.total_positions,
				"status_open" = authed ? status_open["enable"]: 0,
				"status_close" = authed ? status_close["enable"] : 0,
				"desc_open" = status_open["desc"],
				"desc_close" = status_close["desc"])))
		data["slots"] = pos

	data["src"] = "\ref[src]"
	data["station_name"] = station_name()


	if(!mod_mode)
		data["manifest"] = list()
		var/list/crew = list()
		for(var/datum/data/record/t in sortRecord(data_core.general))
			crew.Add(list(list(
				"name" = t.fields["name"],
				"rank" = t.fields["rank"])))

		data["manifest"] = crew
	data["assignments"] = show_assignments
	if(computer)
		data["have_id_slot"] = !!computer.card_slot
		data["have_printer"] = !!computer.nano_printer
		if(!computer.card_slot && mod_mode == 1)
			mod_mode = 0 //We can't modify IDs when there is no card reader
	else
		data["have_id_slot"] = 0
		data["have_printer"] = 0

	data["centcom_access"] = is_centcom


	data["authenticated"] = authed


	if(mod_mode == 1)

		if(computer && computer.card_slot)
			var/obj/item/weapon/card/id/id_card = computer.card_slot.stored_card

			data["has_id"] = !!id_card
			data["id_rank"] = id_card && id_card.assignment ? html_encode(id_card.assignment) : "Unassigned"
			data["id_owner"] = id_card && id_card.registered_name ? html_encode(id_card.registered_name) : "-----"
			data["id_name"] = id_card ? strip_html_simple(id_card.name) : "-----"

			if(show_assignments)
				data["engineering_jobs"] = format_jobs(engineering_positions)
				data["medical_jobs"] = format_jobs(medical_positions)
				data["science_jobs"] = format_jobs(science_positions)
				data["security_jobs"] = format_jobs(security_positions)
				data["cargo_jobs"] = format_jobs(supply_positions)
				data["civilian_jobs"] = format_jobs(civilian_positions)
				data["centcom_jobs"] = format_jobs(get_all_centcom_jobs())


		if(computer.card_slot.stored_card)
			var/obj/item/weapon/card/id/id_card = computer.card_slot.stored_card
			if(is_centcom)
				var/list/all_centcom_access = list()
				for(var/access in get_all_centcom_access())
					all_centcom_access.Add(list(list(
						"desc" = replacetext(get_centcom_access_desc(access), "&nbsp", " "),
						"ref" = access,
						"allowed" = (access in id_card.access) ? 1 : 0)))
				data["all_centcom_access"] = all_centcom_access
			else
				var/list/regions = list()
				for(var/i = 1; i <= 7; i++)
					if((minor || target_dept) && !(i in region_access))
						continue

					var/list/accesses = list()
					if(i in reg_ids)
						for(var/access in get_region_accesses(i))
							if (get_access_desc(access))
								accesses.Add(list(list(
								"desc" = replacetext(get_access_desc(access), "&nbsp", " "),
								"ref" = access,
								"allowed" = (access in id_card.access) ? 1 : 0)))

					regions.Add(list(list(
						"name" = get_region_accesses_name(i),
						"regid" = i,
						"selected" = (i in reg_ids) ? 1 : null,
						"accesses" = accesses)))
				data["regions"] = regions

	data["minor"] = target_dept || minor ? 1 : 0


	return data


/datum/computer_file/program/card_mod/proc/build_manage(datum/job,open = 0)
	var/out = "Denied"
	var/can_change= 0
	if(open)
		can_change = can_open_job(job)
	else
		can_change = can_close_job(job)
	var/enable = 0
	if(can_change == 1)
		out = "[open ? "Open Position" : "Close Position"]"
		enable = 1
	else if(can_change == -2)
		var/time_to_wait = round(change_position_cooldown - ((world.time / 10) - time_last_changed_position), 1)
		var/mins = round(time_to_wait / 60)
		var/seconds = time_to_wait - (60*mins)
		out = "Cooldown ongoing: [mins]:[(seconds < 10) ? "0[seconds]" : "[seconds]"]"
	else
		out = "Denied"

	return list("enable" = enable, "desc" = out)


/datum/computer_file/program/card_mod/proc/authorized()
	if(!authenticated)
		if(computer && computer.card_slot)
			var/obj/item/weapon/card/id/auth_card = computer.card_slot.stored_card2
			if(auth_card)
				region_access = list()
				if(transfer_access in auth_card.GetAccess())
					minor = 0
					authenticated = 1
					return 1
				else
					if((access_hop in auth_card.access) && ((target_dept==1) || !target_dept))
						region_access |= 1
						region_access |= 6
						get_subordinates("Head of Personnel")
					if((access_hos in auth_card.access) && ((target_dept==2) || !target_dept))
						region_access |= 2
						get_subordinates("Head of Security")
					if((access_cmo in auth_card.access) && ((target_dept==3) || !target_dept))
						region_access |= 3
						get_subordinates("Chief Medical Officer")
					if((access_rd in auth_card.access) && ((target_dept==4) || !target_dept))
						region_access |= 4
						get_subordinates("Research Director")
					if((access_ce in auth_card.access) && ((target_dept==5) || !target_dept))
						region_access |= 5
						get_subordinates("Chief Engineer")
					if(region_access)
						minor = 1
						authenticated = 1
						return 1
	else
		return authenticated

/datum/computer_file/program/card_mod/proc/get_subordinates(rank)
	head_subordinates = list()
	for(var/datum/job/job in SSjob.occupations)
		if(rank in job.department_head)
			head_subordinates += job.title
