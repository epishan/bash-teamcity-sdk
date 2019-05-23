#!/usr/bin/env bash
set -e

TC_API_URL=http://teamcity.internal.lel.asia/httpAuth/app/rest

get_build_type_id(){

    if [ $# -lt 3 ] ; then
        echo "Usage: $0 <system>"
        exit 1
    fi

    sys=$1
    type=$2
    suffix=$3
    team=$4

    case $sys in

        ## Technogise
        'ist')                echo "Ops_Ist_${type}_${suffix}" ;;
        'rms')                echo "Ops_Rms_${type}_${suffix}" ;;
        'dop')                echo "Ops_Dop_${type}_${suffix}" ;;
        'sbm')                echo "Ops_Sbm_${type}_${suffix}" ;;
        'stt')                echo "Ops_Stt_${type}_${suffix}" ;;
        'sofp')               echo "Ops_Sofp_${type}_${suffix}" ;;

        ## Legion
        'imspackage')         echo "Lel_TeamLegion_Ims_PackageGo_${type}_${suffix}" ;;
        'ims_package')        echo "Lel_TeamLegion_Ims_Package_${type}_${suffix}" ;;
        'ims_cod')            echo "Lel_TeamLegion_Ims_Cod_${type}_${suffix}" ;;
        'ims_rating')         echo "Lel_TeamLegion_Ims_Rating_${type}_${suffix}" ;;
        'ims_finance')        echo "Lel_TeamLegion_Ims_Finance_${type}_${suffix}" ;;
        'ims_auth')           echo "Lel_TeamLegion_Ims_Auth_${type}_${suffix}" ;;
        'imseventbus')        echo "Lel_TeamLegion_ImsEventbus_${type}_${suffix}" ;;
        'ims_file_manager')   echo "Lel_TeamLegion_Ims_File_Manager_${type}_${suffix}" ;;
        'ims_user')           echo "Lel_TeamLegion_Ims_User_${type}_${suffix}" ;;

        'orders')             echo "Lel_TeamLegion_Orders_${type}_${suffix}" ;;
        'shippers')           echo "Lel_TeamLegion_Shippers_${type}_${suffix}" ;;
        'stocks')             echo "Lel_TeamLegion_Stocks_${type}_${suffix}" ;;
        'warehouse')          echo "Lel_TeamLegion_Warehouse_${type}_${suffix}" ;;

        ## Storm
        #
        'claims')             echo "Lel_TeamStorm_Claims_${type}_${suffix}" ;;
        'addresses')          echo "Lel_TeamStorm_Addresses_${type}_${suffix}" ;;
        'addressesnominatim') echo "Lel_TeamStorm_AddressesNominatim_${type}_${suffix}" ;;
        'addressesosm')       echo "Lel_TeamStorm_AddressesOsm_${type}_${suffix}" ;;
        'addressesphoton')    echo "Lel_TeamStorm_AddressesPhoton_${type}_${suffix}" ;;
        'shippingproviders')  echo "Lel_TeamStorm_ShippingProviders_${type}_${suffix}" ;;
        'stations')           echo "Lel_TeamStorm_Stations_${type}_${suffix}" ;;
        'trackingnumbers')    echo "Lel_TeamStorm_TrackingNumbers_${type}_${suffix}" ;;
        'users')              echo "Lel_TeamStorm_Users_${type}_${suffix}" ;;
        'task')               echo "Lel_TeamStorm_Task_${type}_${suffix}" ;;
        'airwaybills')        echo "Lel_TeamStorm_AirwayBills_${type}_${suffix}" ;;
        'smartrouting')       echo "Lel_TeamStorm_Smartrouting_${type}_${suffix}" ;;

        *)                    echo "Lel_${team}_${sys}_${type}_${suffix}" ;;
    esac

}


get_vcs_id(){
    if [ $# -lt 1 ] ; then
        echo "Usage: $0 <system>"
        exit 1
    fi

    sys=$1
    suffix=$2

    local basename
    case $sys in

        ## Storm
        #
        'claims')             basename="Lel_Claims" ;;
        'addresses')          basename="Lel_Addresses" ;;
        'addressesnominatim') basename="Lel_AddressesNominatim" ;;
        'addressesosm')       basename="Lel_AddressesOsm" ;;
        'addressesphoton')    basename="Lel_AddressesPhoton" ;;
        'shippingproviders')  basename="Lel_ShippingProviders" ;;
        'stations')           basename="Lel_Stations" ;;
        'trackingnumbers')    basename="Lel_TrackingNumbers" ;;
        'users')              basename="Lel_Users" ;;
        'task')               basename="Lel_Task" ;;
        'airwaybills')        basename="Lel_AirwayBills" ;;
        'smartrouting')       basename="Lel_SmartRouting" ;;

        # Vision
        'nms')                basename="Lel_Nms" ;;

        # lazy defining
        *)                    basename="Lel_${sys}" ;;
    esac

    if [[ -z "$suffix" ]]; then
      echo $basename
    else
      echo "${basename}${suffix}"
    fi
}

function _copy_project() {

  local PROJECT_NAME=$1
  local PROJECT_ID=$2
  local SRC_PROJECT_ID=$3
  local PARENT_PROJECT_ID=$4


  resp=$(curl -ns -0 -I -X GET -o /dev/null -w "%{http_code}" "${TC_API_URL}/projects/id:$PARENT_PROJECT_ID")
  if [ $resp != 200 ]; then
    echo "Parent Project with ID:$PARENT_PROJECT_ID doesn't exists, skipping"
    exit
  fi

  resp=$(curl -ns -0 -X GET -H 'Accept:application/json' "${TC_API_URL}/projects/id:$PARENT_PROJECT_ID" | jq '."projects"."project"[] | .name')
  if echo "$resp"|grep "$PROJECT_NAME"; then
    echo "Project with name: '$PROJECT_NAME' already exists in parent project, skipping"
    return
  fi

  resp=$(curl -ns -0 -I -X GET -o /dev/null -w "%{http_code}" "${TC_API_URL}/projects/id:$PROJECT_ID")
  if [ $resp == 200 ]; then
    echo "Target Project with ID:$PROJECT_ID already exists, skipping"
    return
  fi

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

function _build_config_get_vcs() {
  set -e
  local BUILD_TYPE_ID=$1
  local VCS_ID=$2

  curl -n -0 -X GET "${TC_API_URL}/buildTypes/${BUILD_TYPE_ID}/vcs-root-entries" \
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


function copy_secrets() {
  team=$1
  shift
  src_repo=~/repos/LELC/kubernetes-cluster
  dst_path=~/repos/LELS/
  cd $src_repo && git pull
  cd $dst_path && rm -rf secrets-${team}
  git clone ssh://git@bitbucket.lzd.co/lels/secrets-${team}.git && cd secrets-${team} && mkdir -p production
  for sys in "$@"; do
     cp $src_repo/secret/production/$sys.yml $dst_path/secrets-${team}/production/ || echo "Secret doesn't exist for $sys"
  done
  git add .
  git commit -am "Copy secrets for Team ${team}"
}

SYSTEMS="dop dopmobile rms ist sbm shipnet sofp stt"
BUILD_TYPE_ID=Ops_DeployInOpsCluster
#BUILD_TYPE_ID=Ops_KubernetesClusterDeployment_Deploy
#BUILD_TYPE_ID=Ops_KubernetesClusterDeployment_AliStaging_Deploy

for sys in $SYSTEMS; do
   vcs_id=$(get_vcs_id $sys)
   _delete_vcs $BUILD_TYPE_ID $vcs_id
     vcs_id=$(get_vcs_id $sys "role")
     _delete_vcs $BUILD_TYPE_ID $vcs_id
done

#copy_secrets sunrise airflow
#setup_new_projects TeamSunrise airflow

#delete_vcs Lel_PlatformMiddleware_ApiGateway_Deploy_DeployLiveLegacy

# ALL_VCS=$(get_all_vcs)
# for id in $ALL_VCS; do
#   _get_vcs_property $id "url"; echo "  $id";
# done
