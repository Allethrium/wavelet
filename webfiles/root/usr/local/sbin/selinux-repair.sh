#!/bin/bash

# Repairs multiple annoying SElinux denials which break spinup process
cd /var/roothome/
echo -e "
module selinux_repair 1.0;

require {
	type var_run_t;
	type groupadd_t;
	type coreos_boot_mount_generator_t;
	type gssproxy_var_lib_t;
	type systemd_generic_generator_t;
	type user_home_t;
	type init_t;
	class file { getattr open read write };
	class dir add_name;
}

#============= coreos_boot_mount_generator_t ==============
allow coreos_boot_mount_generator_t var_run_t:file { getattr open read };

#============= groupadd_t ==============
allow groupadd_t user_home_t:file write;

#============= init_t ==============
allow init_t gssproxy_var_lib_t:dir add_name;

#============= systemd_generic_generator_t ==============
allow systemd_generic_generator_t var_run_t:file getattr;" > /var/roothome/selinux_repair.te
checkmodule -M -m -o selinux_repair.mod selinux_repair.te; semodule_package -o selinux_repair.pp -m selinux_repair.mod; semodule -i selinux_repair.pp
systemctl restart audit-rules.service 