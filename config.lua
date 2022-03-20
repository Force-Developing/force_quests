ConfigDeliverCargo = {
    MainPedPos = vector3(-905.60809326172, -2338.1669921875, 6.7090291976929),
    MainPedHeading = 330.0,
    MainPedModel = 'a_m_y_cyclist_01',

    MainTruck = {
        {name = mainTruck, hasSpawned = false, model = 'packer', x = -918.65393066406, y = -2326.6188964844, z = 6.7090907096863, h = 330.0},
    },

    Trailer = {
        {name = trailer, hasSpawned = false, model = 'trailers', x = -934.63226318359, y = -2315.3811035156, z = 6.7090835571289, h = 330.0,},
    },

    TrailerDeliverPos = vector3(-338.14666748047, 6143.3671875, 31.485055923462),

    LeaveTruck = vector3(-918.65393066406, -2326.6188964844, 6.7090907096863),

    DeliverCargoMaxReward = 5000,
    DeliverCargoMinReward = 2000,
}

ConfigPickupBoxes = {
    MainVehicle = {
        {name = mainVehicle, model = 'mesa', x = -914.53155517578, y = -2332.3776855469, z = 6.7090907096863, h = 60.0, hasSpawned = false},
    },

    PickUpPos = {
        {hasPickedUp = false, hasSpawned = false, objectName = 'box1', objectHash = 'prop_cs_cardbox_01', x = -180.99502563477, y = 581.34368896484, z = 197.62799072266 - 0.985},
        {hasPickedUp = false, hasSpawned = false, objectName = 'box2', objectHash = 'prop_cs_rub_box_01', x = -179.05497741699, y = 581.10760498047, z = 197.62799072266 - 0.985},
        {hasPickedUp = false, hasSpawned = false, objectName = 'box3', objectHash = 'prop_cardbordbox_03a', x = -176.96315002441, y = 581.33813476563, z = 197.62797546387 - 0.985},
        {hasPickedUp = false, hasSpawned = false, objectName = 'box4', objectHash = 'prop_cardbordbox_04a', x = -179.67127990723, y = 582.79693603516, z = 197.62797546387 - 0.985},
    },

    pickUpPositions = 4,

    DeliverCargoMaxReward = 5000,
    DeliverCargoMinReward = 2000,
}

ConfigTrashCar = {
    MainVehicle = {
        {name = mainVehicle, model = 'rhapsody', x = -914.53155517578, y = -2332.3776855469, z = 6.7090907096863, h = 60.0, hasSpawned = false},
    },

    TrashVehicle = {
        {name = mainTrashVehicle, model = 'rebel', x = -507.81173706055, y = -1707.6998291016, z = 19.312343597412, h = 210.0, hasSpawned = false},
    },

    BulldozerVehicle = {
        {name = mainBulldozerVehicle, model = 'bulldozer', x = -426.65054321289, y = -1689.7595214844, z = 19.029064178467, h = 160.0, hasSpawned = false},
    },

    TrashCarMaxReward = 5000,
    TrashCarMinReward = 2000,
}

ConfigClean = {

    BorstePos = {
        {x = -907.11761474609, y = -2336.0744628906, z = -3.5075182914734, h = 19.0, hasDone = false},
        {x = -900.14215087891, y = -2326.2302246094, z = -3.5075194835663, h = 300.0, hasDone = false},
        {x = -904.74957275391, y = -2317.5009765625, z = -3.5077013969421, h = 115.0, hasDone = false},
    },

    BlowPos = {
        {x = -897.46856689453, y = -2315.8793945313, z = -3.5077650547028, h = 240.0, hasDone = false},
        {x = -887.30639648438, y = -2309.0385742188, z = -3.5077683925629, h = 320.0, hasDone = false},
        {x = -871.39514160156, y = -2318.630859375, z = -3.5077650547028, h = 210.0, hasDone = false},
    },

    CleanPos = {
        {x = -883.06359863281, y = -2317.3100585938, z = -3.5077664852142, h = 340.0, hasDone = false},
        {x = -881.36492919922, y = -2313.8405761719, z = -3.5077664852142, h = 160.0, hasDone = false},
        {x = -916.85003662109, y = -2341.9479980469, z = -3.5075206756592, h = 155.0, hasDone = false},
    },

    CleanRadius = vector3(-901.12890625, -2318.0783691406, -3.5024011135101),

    MaxCleanPositions = 9,

    CleanMaxReward = 5000,
    CleanMinReward = 2000,
}