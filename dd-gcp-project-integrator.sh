#/usr/bin/env bash

# Piping to files until i learn the true power of jq
DD_PROJECTS=dd_projects.txt
GCP_PROJECTS=gcp_projects.txt

# Until we figure out a better and safer way to store the service account key 
# for datadog-ingest-sa@xxxx.iam.gserviceaccount.com
# which is used by datadog gcp-platform integration to fetch logs/metrics for each knp-project
# we rely on kubernetes secrets, mounted as a file.
GCP_KNP_PROJECTS_SA="/secrets/google-knp-projects-sa/key.json"

# Same goes for the key's used for dealing with datadog api.
DD_KNP_PROJECTS_API_KEY=$(< /secrets/datadog-knp-projects-keys/api.key)
DD_KNP_PROJECTS_APP_KEY=$(< /secrets/datadog-knp-projects-keys/app.key)

# Instead of utilizing gcloud cli, we rely on GKE Workload Identity to access GCP for listing projects
# See README.md for more information.
GCP_TOKEN=$(curl -sSL -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token | jq -r '.access_token')
GCP_GET_PROJECTS=$(curl -sSL -H "Authorization: Bearer $GCP_TOKEN" https://cloudresourcemanager.googleapis.com/v1/projects | jq -r '.projects[] | .projectId' |sort -u)

# We want to know which project's are already added as part of the datadog Google cloud platform integration.
# echo to file for later comparison
curl -s -X GET "https://api.datadoghq.eu/api/v1/integration/gcp" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "DD-API-KEY: ${DD_KNP_PROJECTS_API_KEY}" \
  -H "DD-APPLICATION-KEY: ${DD_KNP_PROJECTS_APP_KEY}" \
  |jq -r '.[].project_id | select(startswith("knp-"))' |sort -u > $DD_PROJECTS

# Test if gcp projects list returns empty. (permission error, or simply no projects available ?)
# and echo to file for comparison.
if [[ -z "$GCP_GET_PROJECTS" ]]
  then
    echo "Unable to retrieve projects from GCP"
exit 1
  else
    echo "$GCP_GET_PROJECTS" > $GCP_PROJECTS
  
fi

# Both files are already sorted, so let's check if they differ.
# if cmp returns nothing, then we are good, if not, we first check
# if we forgot to remove a deleted gcp project, in the datadog gcp integration.
# At last, we add missing projects to the datadog integration
if [[ $(cmp $DD_PROJECTS $GCP_PROJECTS | wc -c) -eq 0 ]]
  then
    echo "Everything is in sync."
  exit 0
elif [[ $(comm -23 $DD_PROJECTS $GCP_PROJECTS) ]]
  then
    echo "Project exists in Datadog, but not in GCP"
    echo "Pod exit code should spawn alert!"
  exit 1
else
  for i in $(comm -13 $DD_PROJECTS $GCP_PROJECTS)
    do
      cp $GCP_KNP_PROJECTS_SA "$i.json"
      sed -i "s/project-placeholder/$i/g" "$i.json"
      curl -s -X POST "https://api.datadoghq.eu/api/v1/integration/gcp" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -H "DD-API-KEY: ${DD_KNP_PROJECTS_API_KEY}" \
        -H "DD-APPLICATION-KEY: ${DD_KNP_PROJECTS_APP_KEY}" \
        -d @"$i.json"
      echo "Adding project $i to Datadog's GCP integration"
  done
  exit 0
fi