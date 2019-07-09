CloudFormation do

  Description "#{component_name} - #{component_version}"

  ecs_tags = []
  ecs_tags.push({ Key: 'Name', Value: FnSub("${EnvironmentName}-#{component_name}") })
  ecs_tags.push({ Key: 'EnvironmentName', Value: Ref(:EnvironmentName) })
  ecs_tags.push({ Key: 'EnvironmentType', Value: Ref(:EnvironmentType) })
  ecs_tags.push(*tags.map {|k,v| {Key: k, Value: FnSub(v)}}).uniq { |h| h[:Key] } if defined? tags

  ECS_Cluster('EcsCluster') {
    ClusterName FnSub("${EnvironmentName}-#{cluster_name}") if defined? cluster_name
    Tags(ecs_tags)
  }

  if enable_ec2_cluster

    Condition('IsScalingEnabled', FnEquals(Ref('EnableScaling'), 'true'))
    Condition("SpotPriceSet", FnNot(FnEquals(Ref('SpotPrice'), '')))
    Condition('KeyNameSet', FnNot(FnEquals(Ref('KeyName'), '')))

    EC2_SecurityGroup "SecurityGroupEcs" do
      VpcId Ref('VPCId')
      GroupDescription FnSub("${EnvironmentName}-#{component_name}")
      SecurityGroupEgress ([
        {
          CidrIp: "0.0.0.0/0",
          Description: "outbound all for ports",
          IpProtocol: -1,
        }
      ])
      Tags ecs_tags
    end

    security_groups.each do |sg|
      EC2_SecurityGroupIngress("SecurityGroupRule#{sg['name']}") do
        Description FnSub(sg['desc']) if sg.has_key? 'desc'
        IpProtocol (sg.has_key?('protocol') ? sg['protocol'] : 'tcp')
        FromPort sg['from']
        ToPort (sg.key?('to') ? sg['to'] : sg['from'])
        GroupId FnGetAtt("SecurityGroupEcs",'GroupId')
        SourceSecurityGroupId sg.key?('securty_group') ? FnSub(sg['source_securty_group_ip']) : FnGetAtt("SecurityGroupEcs",'GroupId') unless sg.has_key?('cidrip')
        CidrIp sg['cidrip'] if sg.has_key?('cidrip')
      end
    end if defined? security_groups

    EC2_SecurityGroupIngress('LoadBalancerIngressRule') do
      Description 'Ephemeral port range for ECS'
      IpProtocol 'tcp'
      FromPort '32768'
      ToPort '65535'
      GroupId FnGetAtt('SecurityGroupEcs','GroupId')
      SourceSecurityGroupId Ref('SecurityGroupLoadBalancer')
    end

    EC2_SecurityGroupIngress('BastionIngressRule') do
      Description 'SSH access from bastion'
      IpProtocol 'tcp'
      FromPort '22'
      ToPort '22'
      GroupId FnGetAtt('SecurityGroupEcs','GroupId')
      SourceSecurityGroupId Ref('SecurityGroupBastion')
    end

    policies = []
    iam_policies.each do |name,policy|
      policies << iam_policy_allow(name,policy['action'],policy['resource'] || '*')
    end if defined? iam_policies

    Role('Role') do
      AssumeRolePolicyDocument service_role_assume_policy('ec2')
      Path '/'
      Policies(policies)
      Metadata({
        cfn_nag: {
          rules_to_suppress: [
            { id: 'F3', reason: 'future considerations to further define the describe permisions' }
          ]
        }
      })
    end

    InstanceProfile('InstanceProfile') do
      Path '/'
      Roles [Ref('Role')]
    end

    ecs_tags.push({ Key: 'Role', Value: "ecs" })
    ecs_tags.push({ Key: 'Name', Value: FnSub("${EnvironmentName}-ecs-xx") })
    ecs_tags.push(*instance_tags.map {|k,v| {Key: k, Value: FnSub(v)}}).uniq { |h| h[:Key] } if defined? instance_tags

    # Setup userdata string
    instance_userdata = "#!/bin/bash\nset -o xtrace\n"
    instance_userdata << userdata if defined? userdata
    ecs_agent_extra_config.each do |key,value|
      instance_userdata << "echo #{key}=#{value} >> /etc/ecs/ecs.config\n"
    end if defined? ecs_agent_extra_config
    instance_userdata << efs_mount if enable_efs
    instance_userdata << cfnsignal if defined? cfnsignal

    template_data = {
        SecurityGroupIds: [ Ref(:SecurityGroupEcs) ],
        TagSpecifications: [
          { ResourceType: 'instance', Tags: ecs_tags },
          { ResourceType: 'volume', Tags: ecs_tags }
        ],
        UserData: FnBase64(FnSub(instance_userdata)),
        IamInstanceProfile: { Name: Ref(:InstanceProfile) },
        KeyName: FnIf('KeyNameSet', Ref('KeyName'), Ref('AWS::NoValue')),
        ImageId: Ref('Ami'),
        Monitoring: { Enabled: detailed_monitoring },
        InstanceType: Ref('InstanceType')
    }

    if defined? spot
      spot_options = {
        MarketType: 'spot',
        SpotOptions: {
          SpotInstanceType: (defined?(spot['type']) ? spot['type'] : 'one-time'),
          MaxPrice: FnSub(spot['price'])
        }
      }
      template_data[:InstanceMarketOptions] = FnIf('SpotPriceSet', spot_options, Ref('AWS::NoValue'))
    end

    if defined? volumes
      template_data[:BlockDeviceMappings] = volumes
    end

    EC2_LaunchTemplate(:LaunchTemplate) {
      LaunchTemplateData(template_data)
    }

    AutoScaling_AutoScalingGroup(:AutoScaleGroup) {
      # UpdatePolicy(update_policy) if defined? update_policy
      # UpdatePolicy(:AutoScalingRollingUpdate, {
      #   MaxBatchSize: '1',
      #   MinInstancesInService: FnIf('SpotPriceSet', 0, Ref('DesiredCapacity')),
      #   SuspendProcesses: %w(HealthCheck ReplaceUnhealthy AZRebalance AlarmNotification ScheduledActions),
      #   PauseTime: 'PT5M'
      # })
      DesiredCapacity Ref('AsgDesired')
      MinSize Ref('AsgMin')
      MaxSize Ref('AsgMax')
      VPCZoneIdentifier Ref('SubnetIds')
      LaunchTemplate({
        LaunchTemplateId: Ref(:LaunchTemplate),
        Version: FnGetAtt(:LaunchTemplate, :LatestVersionNumber)
      })
    }


    Logs_LogGroup('LogGroup') {
      LogGroupName Ref('AWS::StackName')
      RetentionInDays "#{log_group_retention}"
    }

    if defined?(ecs_autoscale)

      if ecs_autoscale.has_key?('custom_scaling')

        default_alarm = {}
        default_alarm['statistic'] = 'Average'
        default_alarm['period'] = '60'
        default_alarm['evaluation_periods'] = '5'

        CloudWatch_Alarm(:ServiceScaleUpAlarm) {
          Condition 'IsScalingEnabled'
          AlarmDescription FnJoin(' ', [Ref('EnvironmentName'), "#{component_name} ecs scale up alarm"])
          MetricName ecs_autoscale['custom_scaling']['up']['metric_name']
          Namespace ecs_autoscale['custom_scaling']['up']['namespace']
          Statistic ecs_autoscale['custom_scaling']['up']['statistic'] || default_alarm['statistic']
          Period (ecs_autoscale['custom_scaling']['up']['period'] || default_alarm['period']).to_s
          EvaluationPeriods ecs_autoscale['custom_scaling']['up']['evaluation_periods'].to_s
          Threshold ecs_autoscale['custom_scaling']['up']['threshold'].to_s
          AlarmActions [Ref(:ScaleUpPolicy)]
          ComparisonOperator 'GreaterThanThreshold'
          Dimensions ecs_autoscale['custom_scaling']['up']['dimensions']
        }

        CloudWatch_Alarm(:ServiceScaleDownAlarm) {
          Condition 'IsScalingEnabled'
          AlarmDescription FnJoin(' ', [Ref('EnvironmentName'), "#{component_name} ecs scale down alarm"])
          MetricName ecs_autoscale['custom_scaling']['down']['metric_name']
          Namespace ecs_autoscale['custom_scaling']['down']['namespace']
          Statistic ecs_autoscale['custom_scaling']['down']['statistic'] || default_alarm['statistic']
          Period (ecs_autoscale['custom_scaling']['down']['period'] || default_alarm['period']).to_s
          EvaluationPeriods ecs_autoscale['custom_scaling']['down']['evaluation_periods'].to_s
          Threshold ecs_autoscale['custom_scaling']['down']['threshold'].to_s
          AlarmActions [Ref(:ScaleDownPolicy)]
          ComparisonOperator 'LessThanThreshold'
          Dimensions ecs_autoscale['custom_scaling']['down']['dimensions']
        }
      end

      if ecs_autoscale.has_key?('memory_high')

        Resource("MemoryReservationAlarmHigh") {
          Condition 'IsScalingEnabled'
          Type 'AWS::CloudWatch::Alarm'
          Property('AlarmDescription', "Scale-up if MemoryReservation > #{ecs_autoscale['memory_high']}% for 2 minutes")
          Property('MetricName','MemoryReservation')
          Property('Namespace','AWS/ECS')
          Property('Statistic', 'Maximum')
          Property('Period', '60')
          Property('EvaluationPeriods', '2')
          Property('Threshold', ecs_autoscale['memory_high'])
          Property('AlarmActions', [ Ref('ScaleUpPolicy') ])
          Property('Dimensions', [
            {
              'Name' => 'ClusterName',
              'Value' => Ref('EcsCluster')
            }
          ])
          Property('ComparisonOperator', 'GreaterThanThreshold')
        }

        Resource("MemoryReservationAlarmLow") {
          Condition 'IsScalingEnabled'
          Type 'AWS::CloudWatch::Alarm'
          Property('AlarmDescription', "Scale-down if MemoryReservation < #{ecs_autoscale['memory_low']}%")
          Property('MetricName','MemoryReservation')
          Property('Namespace','AWS/ECS')
          Property('Statistic', 'Maximum')
          Property('Period', '60')
          Property('EvaluationPeriods', '2')
          Property('Threshold', ecs_autoscale['memory_low'])
          Property('AlarmActions', [ Ref('ScaleDownPolicy') ])
          Property('Dimensions', [
            {
              'Name' => 'ClusterName',
              'Value' => Ref('EcsCluster')
            }
          ])
          Property('ComparisonOperator', 'LessThanThreshold')
        }

      end

      if ecs_autoscale.has_key?('cpu_high')

        Resource("CPUReservationAlarmHigh") {
          Condition 'IsScalingEnabled'
          Type 'AWS::CloudWatch::Alarm'
          Property('AlarmDescription', "Scale-up if CPUReservation > #{ecs_autoscale['cpu_high']}%")
          Property('MetricName','CPUReservation')
          Property('Namespace','AWS/ECS')
          Property('Statistic', 'Maximum')
          Property('Period', '60')
          Property('EvaluationPeriods', '2')
          Property('Threshold', ecs_autoscale['cpu_high'])
          Property('AlarmActions', [ Ref('ScaleUpPolicy') ])
          Property('Dimensions', [
            {
              'Name' => 'ClusterName',
              'Value' => Ref('EcsCluster')
            }
          ])
          Property('ComparisonOperator', 'GreaterThanThreshold')
        }

        Resource("CPUReservationAlarmLow") {
          Condition 'IsScalingEnabled'
          Type 'AWS::CloudWatch::Alarm'
          Property('AlarmDescription', "Scale-up if CPUReservation < #{ecs_autoscale['cpu_low']}%")
          Property('MetricName','CPUReservation')
          Property('Namespace','AWS/ECS')
          Property('Statistic', 'Maximum')
          Property('Period', '60')
          Property('EvaluationPeriods', '2')
          Property('Threshold', ecs_autoscale['cpu_low'])
          Property('AlarmActions', [ Ref('ScaleDownPolicy') ])
          Property('Dimensions', [
            {
              'Name' => 'ClusterName',
              'Value' => Ref('EcsCluster')
            }
          ])
          Property('ComparisonOperator', 'LessThanThreshold')
        }

      end

      Resource("ScaleUpPolicy") {
        Condition 'IsScalingEnabled'
        Type 'AWS::AutoScaling::ScalingPolicy'
        Property('AdjustmentType', 'ChangeInCapacity')
        Property('AutoScalingGroupName', Ref('AutoScaleGroup'))
        Property('Cooldown','300')
        Property('ScalingAdjustment', ecs_autoscale['scale_up_adjustment'])
      }

      Resource("ScaleDownPolicy") {
        Condition 'IsScalingEnabled'
        Type 'AWS::AutoScaling::ScalingPolicy'
        Property('AdjustmentType', 'ChangeInCapacity')
        Property('AutoScalingGroupName', Ref('AutoScaleGroup'))
        Property('Cooldown','300')
        Property('ScalingAdjustment', ecs_autoscale['scale_down_adjustment'])
      }
    end

    Output('EcsSecurityGroup') {
      Value(Ref('SecurityGroupEcs'))
      Export FnSub("${EnvironmentName}-#{component_name}-EcsSecurityGroup")
    }

  end

  Output("EcsCluster") {
    Value(Ref('EcsCluster'))
    Export FnSub("${EnvironmentName}-#{component_name}-EcsCluster")
  }
  Output("EcsClusterArn") {
    Value(FnGetAtt('EcsCluster','Arn'))
    Export FnSub("${EnvironmentName}-#{component_name}-EcsClusterArn")
  }

  if enable_ec2_cluster
    Output("AutoScalingGroupName") {
      Value(Ref('AutoScaleGroup'))
      Export FnSub("${EnvironmentName}-#{component_name}-AutoScalingGroupName")
    }
  end

end
