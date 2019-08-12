CfhighlanderTemplate do

  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', isGlobal: true

    if enable_ec2_cluster
      ComponentParam 'Ami', type: 'AWS::EC2::Image::Id'
      ComponentParam 'EnableScaling', 'false', allowedValues: ['true','false']
      ComponentParam 'SpotPrice', ''

      ComponentParam 'InstanceType'
      ComponentParam 'AsgMin', '1'
      ComponentParam 'AsgMax', '2'
      ComponentParam 'AsgDesired', '1'
      ComponentParam 'KeyName', ''
      ComponentParam 'SubnetIds', type: 'CommaDelimitedList'

      ComponentParam 'VPCId', type: 'AWS::EC2::VPC::Id'
      ComponentParam 'FileSystem' if enable_efs
      
      ComponentParam 'LaunchTemplateVersion', 'latest', allowedValues: ['latest','default']
    end

  end
end
