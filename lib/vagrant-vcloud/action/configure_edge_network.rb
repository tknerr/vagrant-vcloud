require 'awesome_print'

module VagrantPlugins
  module VCloud
    module Action
      class ConfigureEdgeNetwork
        def initialize(app, env)
          @app = app
          @logger = Log4r::Logger.new("vagrant_vcloud::action::ConfigureEdgeNetwork")
        end

        def fetchOldRules(vapp_nat_rules)
          old_nat_rules = []

          # format as needed for input, should be standardized through the while
          # driver though, looks very confusing right now.

          vapp_nat_rules.each do |oRule|
            old_nat_rules << {
              :nat_external_port => oRule[1][:ExternalPort],
              :nat_internal_port => oRule[1][:InternalPort],
              :nat_protocol => oRule[1][:Protocol],
              :vm_scoped_local_id => oRule[1][:VAppScopedVmId] 
            }
          end
          @logger.debug("old_nat_rules: #{old_nat_rules}")
          old_nat_rules
        end

        def generateNewRules(netconfig, vm_scoped_local_id)
        
          # Ensure the ports are changed into strings, or later the 
          # rules comparison will fail, and duplicate rules will be created.

          new_nat_rules = []
          netconfig.each do |rule|
            new_nat_rules << {
              :nat_external_port => rule[:nat_external_port].to_s, # string !
              :nat_internal_port => rule[:nat_internal_port].to_s, # string !
              :nat_protocol => rule[:protocol],
              :vm_scoped_local_id => vm_scoped_local_id
            }
          end
          @logger.debug("new_nat_rules: #{new_nat_rules}")
          new_nat_rules
        end

        def AppendNewRules(oldRules, newRules)

          nat_rules = []

          if oldRules.length() > 0
            @logger.debug("Old rules exists, appending rules")

            # Fetch the differences between rules arrays
            diffRules = newRules.to_a - oldRules.to_a 
            @logger.debug("diffRules: #{diffRules}")

            # Add old rules
            oldRules.each do |oRule|
              nat_rules << {
                :nat_external_port => oRule[:nat_external_port],
                :nat_internal_port => oRule[:nat_internal_port],
                :nat_protocol => oRule[:nat_protocol],
                :vm_scoped_local_id => oRule[:vm_scoped_local_id]
              }
            end

            # Append new rules
            diffRules.each do |dRule|
              nat_rules << dRule
            end  

          else
            # If no rules were available means new rules are default
            @logger.debug("No current rules, newrules are applied")
            nat_rules = newRules

          end

          @logger.debug("nat_rules: #{nat_rules}")
          nat_rules
        end

          
        def call(env)
         
          cfg = env[:machine].provider_config
          cnx = cfg.vcloud_cnx.driver
          netconfig = nil

          vAppId = env[:machine].get_vapp_id
          vmName = env[:machine].name.to_s

          @logger.info("vShield Edge Network configuration...")

          vApp = cnx.get_vapp(vAppId)
          vapp_scoped_local_id = vApp[:vms_hash][:"#{vmName}"][:vapp_scoped_local_id]

          cfg.port_forwarding_rules.each do |node|
            if node[:hostname].to_s == vmName
              netconfig = node[:forwarded_ports]
            end
          end 

          # Fetching current vApp nat rules in specific format
          vapp_nat_rules = cnx.get_vapp_port_forwarding_rules(vAppId)

          # Modifying the format to be reusable in the comparison/append method
          oldvAppRules = fetchOldRules(vapp_nat_rules)

          # Generating the rules from Vagrant Configuration file
          newvAppRules = generateNewRules(netconfig, vapp_scoped_local_id)

          # Appending rules if needed.
          nat_rules = AppendNewRules(oldvAppRules, newvAppRules)
        
          if oldvAppRules != nat_rules
            # Finally apply the port forwarding rules
            @logger.info("Applying new configured port forwarding rules...")
            setrule = cnx.set_vapp_port_forwarding_rules(
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
            wait = cnx.wait_task_completion(setrule)
          
          else
            @logger.info("Rules already configured!")
          end

          @app.call env
          
        end
      end
    end
  end
end
