bits 16

kernel_sector dd 2
kernel_size dd KERNEL_SIZE

model_sector dd MODEL_SECTOR   ; ceil(KERNEL_SIZE / 512) 

times 512 - ($-$$) db 0