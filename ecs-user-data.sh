#!/bin/bash
echo ECS_CLUSTER=hello-ecs-cluster >> /etc/ecs/ecs.config
systemctl enable --now ecs
