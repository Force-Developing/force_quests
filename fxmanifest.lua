fx_version 'cerulean'
lua54 'yes'
game 'gta5'

name 'force_quests'
author 'Force Developments <discord:@force3883>'
description 'Quick jobs from one NPC: deliver a trailer, pick up boxes, scrap a car with a bulldozer or clean the subway. ESX, QBCore and QBox.'
version '2.0.0'

dependencies {
    '/onesync',
    'ox_lib',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/functions.lua',
}

server_scripts {
    'version.lua',
    'server/custom/frameworks/*.lua',
    'server/main.lua',
}

client_scripts {
    'client/custom/frameworks/*.lua',
    'client/interact.lua',
    'client/main.lua',
}

files {
    'locales/*.json',
}
