require "i18n"

module VagrantPlugins
  module VCloud
    module Action
      class PowerOnVApp

        def initialize(app, env)
          @app = app
          @logger = Log4r::Logger.new("vagrant_vcloud::action::PowerOnVApp")
        end

        def configurevAppNetworking(env)

          cfg = env[:machine].provider_config
          cnx = cfg.vcloud_cnx.driver
        
          vAppId = env[:machine].get_vapp_id
      
          @logger.info("vShield Edge Network configuration...")

          vApp = cnx.get_vapp(vAppId)

          nat_rules = []
          
          # Generate all needed nat rules from the vagrant file.
          cfg.port_forwarding_rules.each do |node|
            vmName = node[:hostname]
            node[:forwarded_ports].each do |rule|
              nat_rules << {
                :nat_external_port => rule[:nat_external_port].to_s, # string !
                :nat_internal_port => rule[:nat_internal_port].to_s, # string !
                :nat_protocol => rule[:protocol],
                :vm_scoped_local_id => vApp[:vms_hash][:"#{vmName}"][:vapp_scoped_local_id]
              }
            end
          end 
        
          # Set the rules
          @logger.info("Applying vApp configured port forwarding rules...")
          @logger.debug("Rules: #{nat_rules}")
          setrules = cnx.set_vapp_port_forwarding_rules(
            vAppId, 
            "Vagrant-vApp-Net",
            {
              :fence_mode => "natRouted",
              :parent_network => cfg.vdc_network_id,
              :nat_policy_type => "allowTraffic",
              :nat_rules => nat_rules
            }
          )

          # Wait for vShield Edge Network configuration to complete
          wait = cnx.wait_task_completion(setrules)
        end 

        def call(env)

          cfg = env[:machine].provider_config
          cnx = cfg.vcloud_cnx.driver

          vAppId = env[:machine].get_vapp_id
          vApp = cnx.get_vapp(vAppId)

          currentVMs = vApp[:vms_hash].length()
          totalVMs = cfg.port_forwarding_rules.length()

          @logger.debug("Current VMs #{currentVMs}, Total VMs #{totalVMs}")
          
          if currentVMs == totalVMs

            # Configure vApp vShield Edge port forwarding rules 
            configurevAppNetworking env

            # Once all VMs are available boot the vApp
            env[:ui].info("Powering on vApp Id #{vAppId}")
            task_id = cnx.poweron_vapp(vAppId)
            wait = cnx.wait_task_completion(task_id)
          else
            @logger.debug("Current VMs < Total VMs, not booting vApp...")
          end

          @app.call env
        end
      end
    end
  end
end
