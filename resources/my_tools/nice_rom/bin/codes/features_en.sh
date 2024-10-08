#!/bin/bash
apktool_path="$(dirname "$0")/bin/all/apktool/apktool_2.10.0.jar"

remove_extra_vbmeta_verification() {
    declare -A printed_files
    find "$onepath" -type f -name 'fstab.qcom' -print0 | while IFS= read -r -d '' file; do
        sed -i 's/avb[^,]*,//g' "$file"
        sed -i 's/,avb[^,]*,//g' "$file"
        sed -i 's/,avb[^,]*$//g' "$file"
        # 打印文件路径，如果尚未打印过
        if [[ -z "${printed_files[$file]}" ]]; then
            echo "$file"
            printed_files["$file"]=1
        fi
    done
}

remove_vbmeta_verification() {
    find "$onepath" -type f \( -name 'vbmeta*.avb.json' -o -name 'vendor_boot.avb.json' \) -print0 | while IFS= read -r -d '' file; do
        sed -i '/"rollback_index" : [0-9]\+,/{
        N
        s/\("rollback_index" : [0-9]\+,\)\n    "flags" : [0-9]\+/\1\n    "flags" : 3/
        }' "$file" && echo "$file"
    done
}

remove_device_and_network_verification() {
  while IFS= read -r -d '' settings_apk_path; do
    rm -rf "$(dirname "$settings_apk_path")/oat"
    java -jar "$apktool_path" d -f -r "$settings_apk_path" -o "${settings_apk_path%.apk}"

    while IFS= read -r -d '' smali_file; do
      if [[ "$smali_file" == *"com/android/settings/MiuiDeviceNameEditFragment.smali" ]]; then
        sed -i 's/sget-boolean \([vp][0-9]\+\), Lmiui\/os\/Build;->IS_INTERNATIONAL_BUILD:Z/const\/4 \1, 0x1/' "$smali_file"
        echo -e "Removing device name verification...\n$smali_file"
      fi

      if [[ "$smali_file" == *"com/android/settings/wifi/EditTetherFragment.smali" ]]; then
        sed -i 's/sget-boolean \([vp][0-9]\+\), Lmiui\/os\/Build;->IS_INTERNATIONAL_BUILD:Z/const\/4 \1, 0x1/' "$smali_file"
        echo -e "Removing network verification...\n$smali_file"
      fi

      if [[ "$smali_file" == *"com/android/settings/DeviceNameCheckManager.smali" ]]; then
        sed -i 's/sget-boolean \([vp][0-9]\+\), Lmiui\/os\/Build;->IS_INTERNATIONAL_BUILD:Z/const\/4 \1, 0x1/' "$smali_file"
        echo -e "Removing device name check...\n$smali_file"
      fi

      if [[ "$smali_file" == *"com/android/settings/bluetooth/MiuiBTUtils.smali" ]]; then
        sed -i '/.method public static isInternationalBuild()Z/,/.end method/c\
.method public static isInternationalBuild()Z\n\
    .registers 1\n\
    const/4 v0, 0x1\n\
    return v0\n\
.end method' "$smali_file"

        sed -i '/.method public static isSupportNameComplianceCheck(Landroid\/content\/Context;)Z/,/.end method/c\
.method public static isSupportNameComplianceCheck(Landroid\/content\/Context;)Z\n\
    .registers 1\n\
    const/4 p0, 0x0\n\
    return p0\n\
.end method' "$smali_file"
        echo -e "Removing Bluetooth device name verification and check...\n$smali_file"
      fi
    done < <(find "${settings_apk_path%.apk}" -name '*.smali' -print0)

    java -jar "$apktool_path" b -c -f "${settings_apk_path%.apk}" -o "$settings_apk_path"
    rm -rf "${settings_apk_path%.apk}"
    echo -e "Modifications completed"
  done < <(find "$onepath" -name "Settings.apk" -print0)

  while IFS= read -r -d '' wifi_service_jar_path; do
    java -jar "$apktool_path" d -f -r "$wifi_service_jar_path" -o "${wifi_service_jar_path%.jar}"
    echo -e "Removing network auto-recovery verification...\n$wifi_service_jar_path"

    while IFS= read -r -d '' smali_file; do
      if [[ "$smali_file" == *"com/android/server/wifi/Utils.smali" ]]; then
        sed -i '/.method public static checkDeviceNameIsIllegalSync(Landroid\/content\/Context;ILjava\/lang\/String;)Z/,/.end method/c\
.method public static checkDeviceNameIsIllegalSync(Landroid\/content\/Context;ILjava\/lang\/String;)Z\n\
    .registers 3\n\
    const/4 p0, 0x0\n\
    return p0\n\
.end method' "$smali_file"
        echo "Network auto-recovery verification removed"
      fi
    done < <(find "${wifi_service_jar_path%.jar}" -name '*.smali' -print0)

    java -jar "$apktool_path" b -c -f "${wifi_service_jar_path%.jar}" -o "$wifi_service_jar_path"
    rm -rf "${wifi_service_jar_path%.jar}"
  done < <(find "$onepath" -name "miui-wifi-service.jar" -print0)
}

prevent_theme_reversion() {
  while IFS= read -r -d '' jarfile; do
    if [[ -f "$jarfile" ]]; then
      java -jar "$apktool_path" d -f "$jarfile" -o "${jarfile%.jar}"
      echo "Removing theme reversion..."

      while IFS= read -r -d '' smali_file; do
        echo "$smali_file"
        sed -i '/invoke-static {.*}, Lmiui\/drm\/DrmManager;->isLegal(Landroid\/content\/Context;Ljava\/io\/File;Ljava\/io\/File;)Lmiui\/drm\/DrmManager$DrmResult;/,/move-result-object [a-z0-9]*/{
          s/invoke-static {.*}, Lmiui\/drm\/DrmManager;->isLegal(Landroid\/content\/Context;Ljava\/io\/File;Ljava\/io\/File;)Lmiui\/drm\/DrmManager$DrmResult;//
          s/move-result-object \([a-z0-9]*\)/sget-object \1, Lmiui\/drm\/DrmManager\$DrmResult;->DRM_SUCCESS:Lmiui\/drm\/DrmManager\$DrmResult;/
        }' "$smali_file"
      done < <(find "${jarfile%.jar}" -name "ThemeReceiver.smali" -print0)

      java -jar "$apktool_path" b -api 29 -c -f "${jarfile%.jar}" -o "$jarfile"
      rm -rf "${jarfile%.jar}"
      echo "Modification successful"
    fi
  done < <(find "$onepath" -name "miui-framework.jar" -print0)
}

invoke_native_installer() {
  while IFS= read -r -d '' jarfile; do
    if [[ -f "$jarfile" ]]; then
      java -jar "$apktool_path" d -f "$jarfile" -o "${jarfile%.jar}"
      echo "Invoking Android native installer..."

      local smali_file="${jarfile%.jar}/smali/com/android/server/pm/PackageManagerServiceImpl.smali"
      if [[ -f "$smali_file" ]]; then
        echo "$smali_file"
        sed -i '/.method public checkGTSSpecAppOptMode()V/,/.end method/c\.method public checkGTSSpecAppOptMode()V\n    .registers 1\n    return-void\n.end method' "$smali_file"

        sed -i '/.method public static isCTS()Z/,/.end method/c\.method public static isCTS()Z\n    .registers 1\n\n    const/4 v0, 0x1\n\n    return v0\n.end method' "$smali_file"
      fi

      java -jar "$apktool_path" b -c -f "${jarfile%.jar}" -o "$jarfile"
      rm -rf "${jarfile%.jar}"
      echo "Modification successful"
    fi
  done < <(find "$onepath" -name "miui-services.jar" -print0)
}

remove_unsigned_app_verification() {
  while IFS= read -r -d '' jarfile; do
    java -jar "$apktool_path" d -f -r "$jarfile" -o "${jarfile%.jar}"
    echo "Removing unsigned app verification..."

    while IFS= read -r -d '' smali_file; do
      if sed -n '/invoke-static {.*}, Landroid\/util\/apk\/ApkSignatureVerifier;->getMinimumSignatureSchemeVersionForTargetSdk(I)I/,/move-result [a-z0-9]*/p' "$smali_file" | grep -q 'invoke-static'; then
        sed -i '/invoke-static {.*}, Landroid\/util\/apk\/ApkSignatureVerifier;->getMinimumSignatureSchemeVersionForTargetSdk(I)I/,/move-result [a-z0-9]*/{
          s/invoke-static {.*}, Landroid\/util\/apk\/ApkSignatureVerifier;->getMinimumSignatureSchemeVersionForTargetSdk(I)I//
          s/move-result \([a-z0-9]*\)/const\/4 \1, 0x0/
        }' "$smali_file"
        echo "$smali_file"
      fi
    done < <(find "${jarfile%.jar}" -name '*.smali' -print0)

    java -jar "$apktool_path" b -c -f "${jarfile%.jar}" -o "$jarfile"
    rm -rf "${jarfile%.jar}"
    echo "Modification successful"
  done < <(find "$onepath" -name "services.jar" -print0)
}

copy_dir_xiaomi() {
    declare -A dirs=(["app"]="app" ["data-app"]="data-app" ["priv-app"]="priv-app")
    while IFS= read -r -d '' dir; do
        if [ -d "$dir/bin" ] && [ -d "$dir/media" ] && [ -d "$dir/overlay" ] && [ ! -d "$(dirname "$dir")/etc" ]; then
            for src_dir in "${!dirs[@]}"; do
                dst_dir=${dirs[$src_dir]}
                while IFS= read -r -d '' subdir; do
                    subdir_name=$(basename "$subdir")
                    new_name="${subdir_name#file_locked_}"
                    mkdir -p "$dir/$dst_dir/$new_name"
                    while IFS= read -r -d '' file; do
                        base_name=$(basename "$file" | cut -d. -f1)
                        extension=$(basename "$file" | cut -s -d. -f2)
                        new_base_name=${base_name#Only_}
                        new_file_name="$new_base_name${extension:+.$extension}"
                        echo "$dir/$dst_dir/$new_name"
                        mkdir -p "$(dirname "$dir/$dst_dir/$new_name/$new_file_name")"
                        cp "$file" "$dir/$dst_dir/$new_name/$new_file_name"
                    done < <(find "$subdir" -type f -print0)
                done < <(find "bin/xiaomi/add_for_product/$src_dir" -maxdepth 1 -type d -name "file_locked_*" -print0)
            done
        fi
    done < <(find "$onepath" -type d -name "product" -print0)
}

copy_dir_samsung() {
    declare -A dirs=(["app"]="app" ["preload"]="preload" ["priv-app"]="priv-app")
    while IFS= read -r -d '' dir; do
        if [ -d "$dir/bin" ] && [ -d "$dir/media" ] && [ -d "$dir/preload" ] && [ -d "$dir/etc" ]; then
            for src_dir in "${!dirs[@]}"; do
                dst_dir=${dirs[$src_dir]}
                while IFS= read -r -d '' subdir; do
                    subdir_name=$(basename "$subdir")
                    new_name="${subdir_name#file_locked_}"
                    mkdir -p "$dir/$dst_dir/$new_name"
                    while IFS= read -r -d '' file; do
                        base_name=$(basename "$file" | cut -d. -f1)
                        extension=$(basename "$file" | cut -s -d. -f2)
                        new_base_name=${base_name#Only_}
                        new_file_name="$new_base_name${extension:+.$extension}"
                        echo "$dir/$dst_dir/$new_name"
                        mkdir -p "$(dirname "$dir/$dst_dir/$new_name/$new_file_name")"
                        cp "$file" "$dir/$dst_dir/$new_name/$new_file_name"
                    done < <(find "$subdir" -type f -print0)
                done < <(find "bin/samsung/add_for_system/$src_dir" -maxdepth 1 -type d -name "file_locked_*" -print0)
            done
        fi
    done < <(find "$onepath" -type d -name "system" -print0)
}

replace_files_samsung() {
    local src_dir="$(dirname "$0")/bin/samsung/replace"
    local dst_dir="$onepath"

    for src_file in "$src_dir"/*
    do
        local name=$(basename "$src_file")
        mv "$src_file" "$src_dir/$name"_ready_to_adjust
    done

    echo "Files to be replaced:"
    while IFS= read -r -d '' file; do
        local name=$(basename "$file")
        for src_file_ready_to_adjust in "$src_dir"/*_ready_to_adjust
        do
            if [[ "$src_file_ready_to_adjust" == "$src_dir/$name"_ready_to_adjust ]]; then
                rm -rf "$file"
                cp -r "$src_file_ready_to_adjust" "$(dirname "$file")/$name" > /dev/null && echo "$(dirname "$file")/$name"
            fi
        done
    done < <(find "$dst_dir" -type f -print0)

    echo "Directories to be replaced:"
    while IFS= read -r -d '' dir; do
        local name=$(basename "$dir")
        for src_file_ready_to_adjust in "$src_dir"/*_ready_to_adjust
        do
            if [[ "$src_file_ready_to_adjust" == "$src_dir/$name"_ready_to_adjust ]]; then
                rm -rf "$dir"
                cp -r "$src_file_ready_to_adjust" "$(dirname "$dir")/$name" > /dev/null && echo "$(dirname "$dir")/$name"
            fi
        done
    done < <(find "$dst_dir" -type d -print0)

    for src_file_ready_to_adjust in "$src_dir"/*_ready_to_adjust
    do
        mv  "$src_file_ready_to_adjust" "${src_file_ready_to_adjust%_ready_to_adjust*}"
    done
}

update_build_props() {
  declare -A lines_to_add=(
    [system]="persist.sys.background_blur_supported=true persist.sys.background_blur_status_default=true persist.sys.background_blur_mode=0 persist.sys.background_blur_version=2 debug.game.video.speed=1 debug.game.video.support=1"
    [vendor]="ro.vendor.se.type=HCE,UICC,eSE ro.vendor.audio.sfx.scenario=true"
    [product]="persist.sys.miui_animator_sched.sched_threads=2 persist.vendor.display.miui.composer_boost=4-7"
  )
  while IFS= read -r -d '' dir; do
    local type="${dir##*/}"
    local build_prop_path="$dir/build.prop"
    if [[ "$type" == "product" ]]; then
      build_prop_path="$dir/etc/build.prop"
    fi
    if { [[ "$type" == "system" && -d "$dir/framework" ]] || 
         [[ "$type" == "vendor" && -d "$dir/etc" ]] ||
         [[ "$type" == "product" && -d "$dir/etc" ]]; } && [[ -f "$build_prop_path" ]]; then
      IFS=$'\n' read -d '' -r -a current_lines < "$build_prop_path"
      for key in "${!lines_to_add[@]}"; do
        if [[ "$type" == "$key" ]]; then
          for line in ${lines_to_add[$key]}; do
            local prop_name=$(echo "$line" | cut -d '=' -f 1)
            sed -i "/$prop_name/d" "$build_prop_path"
            echo "$line" >> "$build_prop_path"
          done
        fi
      done
      echo "Updated $type folder's $build_prop_path file."
    fi
  done < <(find "$onepath" -type d \( -name 'system' -o -name 'vendor' -o -name 'product' \) -print0)
}

replace_files_xiaomi() {
    local src_dir="$(dirname "$0")/bin/xiaomi/replace"
    local dst_dir="$onepath"

    for src_file in "$src_dir"/*
    do
        local name=$(basename "$src_file")
        mv "$src_file" "$src_dir/$name"_ready_to_adjust
    done

    echo "Files to be replaced:"
    # Process files
    while IFS= read -r -d '' file; do
        local name=$(basename "$file")
        for src_file_ready_to_adjust in "$src_dir"/*_ready_to_adjust
        do
            if [[ "$src_file_ready_to_adjust" == "$src_dir/$name"_ready_to_adjust ]]; then
                rm -rf "$file"
                cp -r "$src_file_ready_to_adjust" "$(dirname "$file")/$name" > /dev/null && echo "$(dirname "$file")/$name"
            fi
        done
    done < <(find "$dst_dir" -type f -print0)

    echo "Directories to be replaced:"
    # Process directories
    while IFS= read -r -d '' dir; do
        local name=$(basename "$dir")
        for src_file_ready_to_adjust in "$src_dir"/*_ready_to_adjust
        do
            if [[ "$src_file_ready_to_adjust" == "$src_dir/$name"_ready_to_adjust ]]; then
                rm -rf "$dir"
                cp -r "$src_file_ready_to_adjust" "$(dirname "$dir")/$name" > /dev/null && echo "$(dirname "$dir")/$name"
            fi
        done
    done < <(find "$dst_dir" -type d -print0)

    for src_file_ready_to_adjust in "$src_dir"/*_ready_to_adjust
    do
        mv  "$src_file_ready_to_adjust" "${src_file_ready_to_adjust%_ready_to_adjust*}"
    done
}

csc_feature_add() {
    local csc_features_need_path="$(dirname "$0")/bin/samsung/csc_add/csc_features_need"
    local lines=("SupportRealTimeNetworkSpeed" "VoiceCall_ConfigRecording" "Camera_EnableCameraDuringCall" "Camera_EnableCameraDuringCall")  # Network speed display, call recording

    decode_csc > /dev/null 2>&1

    while IFS= read -r -d '' filepath; do
        for line in "${lines[@]}"; do
            if grep -q "$line" "$filepath"; then
                sed -i "/$line/d" "$filepath"
            fi
        done
    done < <(find "$onepath" -name "cscfeature_decoded.xml" -print0)

    while IFS= read -r line; do
        while IFS= read -r -d '' filepath; do
            gawk -i inplace -v line="$line" '{if (NR==FNR && /<\/FeatureSet>/) {print line} print}' "$filepath"
        done < <(find "$onepath" -name "cscfeature_decoded.xml" -print0)
    done < "$csc_features_need_path"

    echo "Added features:"
    while IFS= read -r line; do
        echo "$line"
    done < "$csc_features_need_path"

    encode_csc > /dev/null 2>&1
}

decode_csc() {
    local script_dir=$(dirname "$0")
    local omc_decoder_path="$script_dir/bin/samsung/csc_tool/omc-decoder.jar"
    local input_file
    local output_file
    for file in "cscfeature.xml" "customer_carrier_feature.json"; do
        while IFS= read -r -d '' filepath; do
            echo "Found file: $filepath"
            echo "Decoding $file ..."
            input_file="$filepath"
            output_file="${filepath%.*}_decoded.${filepath##*.}"
            java -jar "$omc_decoder_path" -i "$input_file" -o "$output_file"
            rm "$input_file"  # Delete the original file
        done < <(find "$onepath" -name "$file" -print0)
    done
}

encode_csc() {
    local script_dir=$(dirname "$0")
    local omc_decoder_path="$script_dir/bin/samsung/csc_tool/omc-decoder.jar"
    local input_file
    local output_file
    local original_file
    for file in "cscfeature_decoded.xml" "customer_carrier_feature_decoded.json"; do
        while IFS= read -r -d '' filepath; do
            echo "Found file: $filepath"
            echo "Encoding $file ..."
            input_file="$filepath"
            output_file="${filepath/_decoded/}"
            java -jar "$omc_decoder_path" -e -i "$input_file" -o "$output_file"
            rm "$input_file"  # Delete the decoded file
        done < <(find "$onepath" -name "$file" -print0)
    done
}

deodex() {
    local found=false
    local exclude_files=("example")
    local exclude_string=""
    for exclude in "${exclude_files[@]}"; do
        exclude_string+=" -not -iname $exclude"
    done
    for file in "oat" "*.art" "*.oat" "*.vdex" "*.odex" "*.fsv_meta" "*.bprof" "*.prof"; do
        if find "$onepath" -name "$file" $exclude_string -print0 | xargs -0 | grep -q .; then
            if [ "$found" = false ]; then
                echo "Delete list:"
                found=true
            fi
            find "$onepath" -name "$file" $exclude_string -print0 | xargs -0 -I {} sh -c 'echo "{}"; rm -rf "{}"'
        fi
    done
    if [ "$found" = false ]; then
        echo "No odex-related files to delete"
    fi
}

deodex_key_files() {
    local found=false
    local files=("services.*" "miui-services.*" "miui-framework.*" "miui-wifi-service.*")
    for file in "${files[@]}"; do
        if find "$onepath" -name "$file" -not -name "*.jar" -print0 | xargs -0 | grep -q .; then
            if [ "$found" = false ]; then
                echo "Critical delete list:"
                found=true
            fi
            find "$onepath" -name "$file" -not -name "*.jar" -print0 | xargs -0 -I {} sh -c 'echo "{}"; rm -rf "{}"'
        fi
    done
    if [ "$found" = false ]; then
        echo "No related files to delete"
    fi
}

remove_all() {
    for opt in "${options_order[@]}"; do
            remove_files "${options[$opt]}"
    done
}

remove_files() {
    local exclude_files=("samsungpass" "KnoxDesktopLauncher")
    local exclude_string=""
    for exclude in "${exclude_files[@]}"; do
        exclude_string+=" -not -iname $exclude"
    done
    for file in $@; do
        while IFS= read -r -d '' dir
        do
            base_name=$(basename "$dir")
            if find "$dir" -iname "$base_name.apk" | grep -q .; then
                echo "$dir ..."
                rm -rf "$dir"
            fi
        done < <(find "$onepath" -depth -type d -iname "$file" $exclude_string -print0)
    done
}
