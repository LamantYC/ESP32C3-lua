audio.on(0, function(id, event)
    --使用play来播放文件时只有播放完成回调
    local succ,stop,file_cnt = audio.getError(0)
    if not succ then
        if stop then
            log.info("用户停止播放")
        else
            log.info("第", file_cnt, "个文件解码失败")
        end
    end
    -- log.info("播放完成一个音频")
    sys.publish("AUDIO_PLAY_DONE")
end)


-- es8311器件地址
local es8311_address = 0x18

-- es8311初始化寄存器配置
local es8311_reg = {
	{0x45,0x00},
	{0x01,0x30},
	{0x02,0x10},
	{0x02,0x00},
	{0x03,0x10},
	{0x16,0x24},
	{0x04,0x20},
	{0x05,0x00},
	{0x06,(0<<5) + 4 -1},
	{0x07,0x00},
	{0x08,0xFF},
	{0x09,0x0C},
	{0x0A,0x0C},
	{0x0B,0x00},
	{0x0C,0x00},
	{0x10,(0x1C*0) + (0x60*0x00) + 0x03},
	{0x11,0x7F},
	{0x00,0x80 + (0<<6)},
	{0x0D,0x01},
	{0x01,0x3F + (0x00<<7)},
	{0x14,(0<<6) + (1<<4) + 10},
	{0x12,0x28},
	{0x13,0x00 + (0<<4)},
	{0x0E,0x02},
	{0x0F,0x44},
	{0x15,0x00},
	{0x1B,0x0A},
	{0x1C,0x6A},
	{0x37,0x48},
	{0x44,(0 <<7)},
	{0x17,210},
	{0x32,200},
    {0x00,0x80 + (1<<6)},
}

-- i2s数据接收buffer
local rx_buff = zbuff.create(3200)

-- amr数据存放buffer，尽可能地给大一些
local amr_buff = zbuff.create(10240)

--创建一个amr的encoder
local encoder = codec.create(codec.AMR, false)


-- 录音文件路径
local recordPath = "/record.amr"

-- i2s数据接收回调
local function record_cb(id, buff)
    if buff then
        log.info("I2S", id, "接收了", rx_buff:used())
        codec.encode(encoder, rx_buff, amr_buff)		-- 对录音数据进行amr编码，成功的话这个接口会返回true
    end
end



local function record_task()
	audio.config(0, 25, 1, 6, 200)						
    sys.wait(5000)
	pm.power(pm.DAC_EN, true)							-- 打开es8311芯片供电
    log.info("i2c initial",i2c.setup(0, i2c.FAST))		-- 开启i2c
    i2s.setup(0, 0, 8000, 16, 1, i2s.MODE_I2S)			-- 开启i2s
    i2s.on(0, record_cb) 								-- 注册i2s接收回调
    i2s.recv(0, rx_buff, 3200)
    sys.wait(300)
    for i, v in pairs(es8311_reg) do					-- 初始化es8311
        i2c.send(0,es8311_address,v,1)
    end
    sys.wait(5000)
    i2c.send(0, es8311_address,{0x00, 0x80 + (0<<6)},1)	-- 停止录音
    i2s.stop(0)											-- 停止接收

    log.info("录音5秒结束")
	io.writeFile(recordPath, "#!AMR\n")					-- 向文件写入amr文件标识数据
	io.writeFile(recordPath, amr_buff:query(), "a+b")	-- 向文件写入编码后的amr数据

	i2s.setup(0, 0, 0, 0, 0, i2s.MODE_MSB)
   
	local result = audio.play(0, {recordPath})			-- 请求音频播放
	if result then
		sys.waitUntil("AUDIO_PLAY_DONE")				-- 等待音频播放完毕
	else
														-- 音频播放出错	
	end
	
	uart.setup(1, 115200)								-- 开启串口1
    uart.write(1, io.readFile(recordPath))				-- 向串口发送录音文件
end

sys.taskInit(record_task)