CloudFormation do

  Description "#{component_name} - #{component_version}"

  az_conditions_resources('SubnetCompute', maximum_availability_zones)

  ECS_Cluster('EcsCluster')

  EC2_SecurityGroup('SecurityGroupEcs') do
    GroupDescription FnJoin(' ', [ Ref('EnvironmentName'), component_name ])
    VpcId Ref('VPCId')
  end

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

  Role('Role') do
    AssumeRolePolicyDocument service_role_assume_policy('ec2')
    Path '/'
    Policies(IAMPolicies.new.create_policies([
      'cloudwatch-logs',
      'ecs-service-role',
      'ec2-describe'
    ]))
  end

  InstanceProfile('InstanceProfile') do
    Path '/'
    Roles [Ref('Role')]
  end

  user_data = []
  user_data << "#!/bin/bash\n"
  user_data << "INSTANCE_ID=$(/opt/aws/bin/ec2-metadata --instance-id|/usr/bin/awk '{print $2}')\n"
  user_data << "hostname " 
  user_data << Ref("EnvironmentName")
  user_data << "-ecs-${INSTANCE_ID}\n"
  user_data << "sed '/HOSTNAME/d' /etc/sysconfig/network > /tmp/network && mv -f /tmp/network /etc/sysconfig/network && echo \"HOSTNAME="
  user_data << Ref('EnvironmentName')
  user_data << "-ecs-${INSTANCE_ID}\" >>/etc/sysconfig/network && /etc/init.d/network restart\n"
  user_data << "echo ECS_CLUSTER="
  user_data << Ref("EcsCluster")
  user_data << " >> /etc/ecs/ecs.config\n"
  if enable_efs
    user_data << "mkdir /efs\n"
    user_data << "yum install -y nfs-utils\n"
    user_data << "mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 "
    user_data << Ref("FileSystem")
    user_data << ".efs."
    user_data << Ref("AWS::Region")
    user_data << ".amazonaws.com:/ /efs\n"
  end

  LaunchConfiguration('LaunchConfig') do
    ImageId Ref('Ami')
    InstanceType Ref('InstanceType')
    AssociatePublicIpAddress false
    IamInstanceProfile Ref('InstanceProfile')
    KeyName Ref('KeyName')
    SecurityGroups [ Ref('SecurityGroupEcs') ]
    UserData FnBase64(FnJoin('',user_data))
  end

  AutoScalingGroup('AutoScaleGroup') do
    UpdatePolicy('AutoScalingRollingUpdate', {
      "MinInstancesInService" => "0",
      "MaxBatchSize"          => "1",
      "SuspendProcesses"      => ["HealthCheck","ReplaceUnhealthy","AZRebalance","AlarmNotification","ScheduledActions"]
    })
    LaunchConfigurationName Ref('LaunchConfig')
    HealthCheckGracePeriod '500'
    MinSize Ref('AsgMin')
    MaxSize Ref('AsgMax')
    VPCZoneIdentifier az_conditional_resources('SubnetCompute', maximum_availability_zones)
    addTag("Name", FnJoin("",[Ref('EnvironmentName'), "-ecs-xx"]), true)
    addTag("Environment",Ref('EnvironmentName'), true)
    addTag("EnvironmentType", Ref('EnvironmentType'), true)
    addTag("Role", "ecs", true)
  end

  Logs_LogGroup('LogGroup') {
    LogGroupName Ref('AWS::StackName')
    RetentionInDays "#{log_group_retention}"
  }

  Output('EcsCluster', Ref('EcsCluster'))
  Output('SecurityGroupEcs', Ref('SecurityGroupEcs'))
  
end
