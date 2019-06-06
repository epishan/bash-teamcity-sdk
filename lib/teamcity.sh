#!/usr/bin/env bash
set -e



function _check_project() {

  local PROJECT_TYPE=$1
  local PROJECT_ID=$2
  local PARENT_PROJECT_ID=$3


  resp=$(curl -ns -0 -I -X GET -o /dev/null -w "%{http_code}" "${TC_API_URL}/projects/id:$PARENT_PROJECT_ID")
  if [ $resp != 200 ]; then
    echo "❌ Parent Project with ID:$PARENT_PROJECT_ID doesn't exists"
    return
  fi

  resp=$(curl -ns -0 -X GET -H 'Accept:application/json' "${TC_API_URL}/projects/id:$PARENT_PROJECT_ID" | jq '."projects"."project"[] | .name')
  if echo "$resp"|grep -q "$PROJECT_TYPE"; then
    echo "✅ Project with name: '$PROJECT_TYPE' exists in parent project"
  else
    echo "❌ Project with name: '$PROJECT_TYPE' doesn't exists in parent project"
  fi

  resp=$(curl -ns -0 -I -X GET -o /dev/null -w "%{http_code}" "${TC_API_URL}/projects/id:$PROJECT_ID")
  if [ $resp == 200 ]; then
    echo "✅ Project with expected ID:$PROJECT_ID exists"
  else
    echo "❌ Project with name: ID:$PROJECT_ID doesn't exists in parent project"
    return
  fi

  build_ids=$(curl -ns -0 -X GET -H 'Accept:application/json' "${TC_API_URL}/projects/id:$PROJECT_ID/buildTypes" | jq -r '."buildType"[] | .id ')

  for id in $build_ids; do
    echo -n "::  $id  "
    features=$(curl -ns -0 -X GET -H 'Accept:application/json' "${TC_API_URL}/buildTypes/id:$id/features" | jq -r '."feature"[] | .type' )
    for f in $features; do
      if [ $f == "commit-status-publisher" ]; then
         echo "⚠️ found commit-status-publisher"
         curl -ns -0 -X GET -H 'Accept:application/json' "${TC_API_URL}/buildTypes/id:$id/features" | jq '.' | grep -A1 vcsRootId
      fi
    done
  done

}

function _copy_project() {

  local PROJECT_NAME=$1
  local PROJECT_ID=$2
  local SRC_PROJECT_ID=$3
  local PARENT_PROJECT_ID=$4


  resp=$(curl -ns -0 -I -X GET -o /dev/null -w "%{http_code}" "${TC_API_URL}/projects/id:$SRC_PROJECT_ID")
  if [ $resp != 200 ]; then
    echo "Source Project with ID:$SRC_PROJECT_ID doesn't exists, skipping"
    return
  fi

  curl -ns -0 -X POST -o /dev/null  "${TC_API_URL}/projects/" \
            -H "Content-Type:application/xml" \
            -d "<newProjectDescription name='$PROJECT_NAME' id='$PROJECT_ID' copyAllAssociatedSettings='true'><parentProject locator='id:$PARENT_PROJECT_ID'/><sourceProject locator='id:$SRC_PROJECT_ID'/></newProjectDescription>"
  echo "Project $PROJECT_NAME copied with ID:$PROJECT_ID"

}

function attach_commit_publisher() {
  local BUILD_TYPE_ID=$1
  local VCS_ID=$2

  curl -n -0 -X POST "${TC_API_URL}/buildTypes/${BUILD_TYPE_ID}/features" \
  -H 'Content-Type:application/json'  \
  -d "{\"type\":\"commit-status-publisher\",\"properties\":{\"count\":5,\"property\":[{\"name\":\"publisherId\",\"value\":\"atlassianStashPublisher\"},{\"name\":\"secure:stashPassword\"},{\"name\":\"stashBaseUrl\",\"value\":\"https://bitbucket.lzd.co\"},{\"name\":\"stashUsername\",\"value\":\"lel-devops\"},{\"name\":\"vcsRootId\",\"value\":\"$VCS_ID\"}]}}"

}

function replace_commit_publisher() {
  local BUILD_TYPE_ID=$1
  local FEATURE_ID=$2

  curl -n -0 -X PUT "${TC_API_URL}/buildTypes/${BUILD_TYPE_ID}/features" \
  -H 'Content-Type:application/json'  \
  -d "{\"id\": \"$FEATURE_ID\",\"type\":\"commit-status-publisher\",\"properties\":{\"count\":5,\"property\":[{\"name\":\"publisherId\",\"value\":\"atlassianStashPublisher\"},{\"name\":\"secure:stashPassword\"},{\"name\":\"stashBaseUrl\",\"value\":\"https://bitbucket.lzd.co\"},{\"name\":\"stashUsername\",\"value\":\"lel-devops\"},{\"name\":\"vcsRootId\",\"value\":\"$VCS_ID\"}]}}"

}

function _build_config_add_vcs() {
  set -e
  local BUILD_TYPE_ID=$1
  local VCS_ID=$2
  local CHECKOUT_DIR="$3"

  CHECKOUT_RULES=""
  if [[ -n "$CHECKOUT_DIR" ]]; then
      CHECKOUT_RULES=", \"checkout-rules\":\"+:. => $CHECKOUT_DIR\""
      echo -n " with $CHECKOUT_RULES"
  fi

  resp=$(curl -ns -0 -o /dev/null -w "%{http_code}" -X POST "${TC_API_URL}/buildTypes/${BUILD_TYPE_ID}/vcs-root-entries" \
  -H 'Content-Type:application/json'  \
  -d "{ \"id\": \"${VCS_ID}\", \"vcs-root\": { \"id\": \"${VCS_ID}\" } $CHECKOUT_RULES }")

  echo

  if [ $resp != 200 ]; then
    echo "[ERROR] Couldn't add $VCS_ID"
    return 1
  fi

}

function _build_config_attach_template() {
  set -e
  local BUILD_TYPE_ID=$1
  local TEMPLATE_ID=$2

  resp=$(curl -ns -0 -o /dev/null -w "%{http_code}" -X PUT "${TC_API_URL}/buildTypes/${BUILD_TYPE_ID}/template " \
  -H "Content-Type: text/plain" -d "$TEMPLATE_ID")

  echo

  if [ $resp != 200 ]; then
    echo "[ERROR] Couldn't add $TEMPLATE_ID"
    return 1
  fi

}

function _build_config_get_vcs() {
  set -e
  local BUILD_TYPE_ID=$1

  curl -ns -0 -X GET "${TC_API_URL}/buildTypes/${BUILD_TYPE_ID}/vcs-root-entries" \
  -H 'Accept:application/json'

}

function _get_build_config_parameter {
  BUILD_TYPE_ID=$1
  PARAMETER=$2
  curl -ns -0 -X GET  "${TC_API_URL}/buildTypes/${BUILD_TYPE_ID}/parameters/$PARAMETER" \
            -H "application/xml"
}

function _put_build_config_parameter {
  if [ $# -lt 3 ] ; then
      echo "Usage: $0 build_id param value"
      exit 1
  fi
  BUILD_TYPE_ID=$1
  PARAMETER=$2
  VALUE=$3

  curl -ns -0 -X PUT  "${TC_API_URL}/buildTypes/${BUILD_TYPE_ID}/parameters/$PARAMETER" -d "$VALUE" \
            -H "Content-Type: text/plain"
}

function delete_all_vcs {
  BUILD_TYPE_ID=$1
  VCS_IDS=$(curl -ns -0 -X GET  "${TC_API_URL}/buildTypes/${BUILD_TYPE_ID}/vcs-root-entries" \
            -H "Accept:application/json" | jq -r '."vcs-root-entry"[] | .id')
  for vcs in $VCS_IDS; do
   _delete_vcs $BUILD_TYPE_ID $vcs
   echo "ok"
  done
}

function _delete_vcs {
  BUILD_TYPE_ID=$1
  VCS_ID=$2

  CURL_CMD="curl -ns -X DELETE ${TC_API_URL}/buildTypes/${BUILD_TYPE_ID}/vcs-root-entries/$VCS_ID"
  resp=$($CURL_CMD -I -w "%{http_code}" --output /dev/null)

  if [ $resp != 200 ]; then
    echo -n "[ERROR]  "
    $CURL_CMD
    echo
    return
  fi
  echo "ok"
}

function get_all_vcs {
  VCS_IDS=$(curl -ns -0 -X GET  "${TC_API_URL}/vcs-roots" \
            -H "Accept:application/json" | jq -r '."vcs-root"[]|.id')
  echo $VCS_IDS
}

function _get_vcs_proprties_all {
  VCS_IDS=$1
  curl -ns -0 -X GET  "${TC_API_URL}/vcs-roots/$VCS_IDS/properties/" \
            -H "Accept:application/json"
}

function _get_vcs_property {
  VCS_ID=$1
  VCS_PROPERTY=$2
  curl -ns -0 -X GET  "${TC_API_URL}/vcs-roots/$VCS_ID/properties/$VCS_PROPERTY" \
            -H "application/xml"
}

function _put_vcs_property {
  VCS_ID=$1
  VCS_PROPERTY=$2 #  authMethod teamcity:branchSpec teamcitySshKey url
  PROPERTY_VALUE=$3
  curl -ns -0 -X PUT  "${TC_API_URL}/vcs-roots/$VCS_ID/properties/$VCS_PROPERTY" -d "$PROPERTY_VALUE" \
             -H "Content-Type: text/plain"
}



function replace_vcs_property() {
  VCS_ID=$1
  VCS_PROPERTY=$2
  OLD_PROPERTY_VALUE=$3
  NEW_PROPERTY_VALUE=$4

  prop_key=$(_get_vcs_property $VCS_ID $VCS_PROPERTY)
  echo "Current: $prop_key"
  if [ "$prop_key" == "$OLD_PROPERTY_VALUE" ]; then
     _put_vcs_property $VCS_ID $VCS_PROPERTY "$NEW_PROPERTY_VALUE"
  fi
}


function setup_new_projects() {

  team=$1
  shift
  systems=$@

  # update application value for deploy
  param="application"
  for sys in $systems; do
    echo "sys: $sys"

    # disabled due to not automatically changing snapshot dependency for deploy_live
    # for job_type in "Deploy" "Misc" "CI" "Showrooms"; do
    #   _copy_project "$job_type" "Lel_${team}_${sys}_${job_type}" "Lel_${team}_ServiceSkeleton_$job_type"  "Lel_${team}_${sys}"
    # done

    vcs_id=$(get_vcs_id $sys)
    vcs_id_role=$(get_vcs_id $sys "role")

    for env in "live" "staging"; do

       build_type_id=$(get_build_type_id $sys deploy $env $team)
       echo " buildID: $build_type_id"

         echo -n "  updating parameter '$param', new value: "
         _put_build_config_parameter $build_type_id $param $sys
         echo

         echo -n "  adding vcs root '$vcs_id' "
         _build_config_add_vcs $build_type_id $vcs_id "./$sys"
         echo

         if [[ "$env" == "live" ]]; then
            echo -n "  adding vcs root 'Lel_${team}_Secrets' "
            _build_config_add_vcs $build_type_id Lel_${team}_Secrets "./secrets"
            echo
         fi

    done



    for action in "MasterMerge" "MergeTicket"; do
        build_type_id=$(get_build_type_id $sys Misc $action $team)
        echo " buildID: $build_type_id"
        echo -n "  adding vcs root '$vcs_id' "
        _build_config_add_vcs $build_type_id $vcs_id

        build_type_id=$(get_build_type_id $sys Misc "${action}Role" $team)
        echo " buildID: $build_type_id"
        echo -n "  adding vcs root '$vcs_id_role' "
        _build_config_add_vcs $build_type_id $vcs_id_role
    done
    echo
  done

}

function check_projects() {

  team=$1
  shift
  systems=$@

  for sys in $systems; do
    echo "💾 sys: $sys"
    JOB_TYPES="Deploy Misc CI Showrooms"
    JOB_TYPES="CI"
    for job_type in $JOB_TYPES; do
       _check_project "$job_type" "Lel_${team}_${sys}_${job_type}" "Lel_${team}_${sys}" # job_type job_id project
    done


  done

}


function check_builds() {

  build_ids=$@

  for id in $build_ids; do

    resp=$(curl -ns -0 -I -X GET -o /dev/null -w "%{http_code}" "${TC_API_URL}/buildTypes/id:$id")
    if [ $resp != 200 ]; then
      echo "❌ Build with name: ID:$id doesn't exists"
    else
      echo -n "::  $id  "
      csp_found=0
      features=$(curl -ns -0 -X GET -H 'Accept:application/json' "${TC_API_URL}/buildTypes/id:$id/features" | jq -r '."feature"[] | .type' )
      for f in $features; do
        if [ $f == "commit-status-publisher" ]; then
           csp_found=1
           echo -n "⚠️ found commit-status-publisher with vcs_root ::: "
           #res=$(curl -ns -0 -X GET -H 'Accept:application/json' "${TC_API_URL}/buildTypes/id:$id/features/" |  jq -r '."feature"[] | select (."type" | contains ("publish") ) | .properties.property[] | select (."name" | contains ("vcsRootId") ) | .value' )
           res=$(curl -ns -0 -X GET -H 'Accept:application/json' "${TC_API_URL}/buildTypes/id:$id/features/" |  jq -r '."feature"[] | select (."type" | contains ("publish") ) ' )

           if [ "$res" == "" ]; then
              echo "❌  EMPTY"
              feature_id=$(curl -ns -0 -X GET -H 'Accept:application/json' "${TC_API_URL}/buildTypes/id:$id/features/" |  jq -r '."feature"[] | select (."type" | contains ("publish") ) | .id ')
              #replace_commit_publisher $id $feature_id
           else
             echo "$res"
           fi
        fi
      done
      if [ $csp_found -eq 0 ]; then
        echo "❌  commit-status-publisher not found"
        vcs_id=$(_build_config_get_vcs $id | jq -r '."vcs-root-entry"[] | .id')
        #attach_commit_publisher $id $vcs_id
      fi

    fi

  done

}
