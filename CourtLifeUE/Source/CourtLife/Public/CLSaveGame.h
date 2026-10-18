#pragma once

#include "CoreMinimal.h"
#include "GameFramework/SaveGame.h"
#include "CLTypes.h"
#include "CLSaveGame.generated.h"

/** All of a profile's MyPlayers. Console builds route this through the platform save system. */
UCLASS()
class COURTLIFE_API UCLSaveGame : public USaveGame
{
	GENERATED_BODY()

public:
	static constexpr int32 MaxSlots = 10;

	UPROPERTY() int32 Version = 1;
	UPROPERTY() TArray<FMyPlayerBuild> Players;

	UFUNCTION(BlueprintCallable, Category = "CourtLife|Save")
	static UCLSaveGame* LoadOrCreate(int32 UserIndex = 0);

	/** Insert or replace by Id. Returns false when all slots are full. */
	UFUNCTION(BlueprintCallable, Category = "CourtLife|Save")
	bool Upsert(const FMyPlayerBuild& Build);

	UFUNCTION(BlueprintCallable, Category = "CourtLife|Save")
	void Remove(const FGuid& Id);

	UFUNCTION(BlueprintCallable, Category = "CourtLife|Save")
	bool Commit(int32 UserIndex = 0);
};
