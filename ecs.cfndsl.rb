CloudFormation do

  Description "#{component_name} - #{component_version}"

  az_conditions_resources('SubnetCompute', maximum_availability_zones)

  asg_ecs_tags = []
  asg_ecs_tags << { Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), component_name, '-xx' ]), PropagateAtLaunch: true }
  asg_ecs_tags << { Key: 'Environment', Value: Ref(:EnvironmentName), PropagateAtLaunch: true}
  asg_ecs_tags << { Key: 'EnvironmentType', Value: Ref(:EnvironmentType), PropagateAtLaunch: true }
  asg_ecs_tags << { Key: 'Role', Value: "ecs", PropagateAtLaunch: true }

  asg_ecs_extra_tags = []
  ecs_extra_tags.each { |key,value| asg_ecs_extra_tags << { Key: "#{key}", Value: value, PropagateAtLaunch: true } } if defined? ecs_extra_tags


  asg_ecs_tags = (asg_ecs_extra_tags + asg_ecs_tags).uniq { |h| h[:Key] }


  ECS_Cluster('EcsCluster') {
    ClusterName FnSub("${EnvironmentName}-#{cluster_name}") if defined? cluster_name
  }

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

  policies = []
  iam_policies.each do |name,policy|
    policies << iam_policy_allow(name,policy['action'],policy['resource'] || '*')
  end if defined? iam_policies

  Role('Role') do
    AssumeRolePolicyDocument service_role_assume_policy('ec2')
    Path '/'
    Policies(policies)
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
  user_data << "echo ECS_ENGINE_TASK_CLEANUP_WAIT_DURATION=10m"
  user_data << " >> /etc/ecs/ecs.config\n"
  user_data << "echo ECS_IMAGE_CLEANUP_INTERVAL=10m"
  user_data << " >> /etc/ecs/ecs.config\n"
  user_data << "echo ECS_IMAGE_MINIMUM_CLEANUP_AGE=5m"
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

  volumes = []
  volumes << {
    DeviceName: '/dev/xvda',
    Ebs: {
      VolumeSize: volume_size
    }
  } if defined? volume_size

  LaunchConfiguration('LaunchConfig') do
    ImageId Ref('Ami')
    BlockDeviceMappings volumes if defined? volume_size
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
    Tags asg_ecs_tags
  end

  Logs_LogGroup('LogGroup') {
    LogGroupName Ref('AWS::StackName')
    RetentionInDays "#{log_group_retention}"
  }

  Output("EcsCluster") {
    Value(Ref('EcsCluster'))
    Export FnSub("${EnvironmentName}-#{component_name}-EcsCluster")
  }
  Output("EcsClusterArn") {
    Value(FnGetAtt('EcsCluster','Arn'))
    Export FnSub("${EnvironmentName}-#{component_name}-EcsClusterArn")
  }
  Output('EcsSecurityGroup') {
    Value(Ref('SecurityGroupEcs'))
    Export FnSub("${EnvironmentName}-#{component_name}-EcsSecurityGroup")
  }

end
