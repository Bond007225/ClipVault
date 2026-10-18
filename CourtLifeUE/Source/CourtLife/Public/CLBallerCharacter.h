#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "CLTypes.h"
#include "CLBallerCharacter.generated.h"

class UCameraComponent;
class USpringArmComponent;
class UInputAction;
class UInputMappingContext;
class UCLShotComponent;
class UCLDribbleComponent;
class UCLCustomizationComponent;
class UCLAnimSet;
class UCLCosmeticsCatalog;
class ACLBasketball;
struct FInputActionValue;

/** Your MyPlayer on the court. */
UCLASS()
class COURTLIFE_API ACLBallerCharacter : public ACharacter
{
	GENERATED_BODY()

public:
	ACLBallerCharacter();

	virtual void BeginPlay() override;
	virtual void Tick(float DeltaSeconds) override;
	virtual void SetupPlayerInputComponent(UInputComponent* PlayerInputComponent) override;

	/** Apply (or re-apply after editing) a build: looks, ratings, jumper, combos. */
	UFUNCTION(BlueprintCallable, Category = "CourtLife")
	void ApplyBuild(const FMyPlayerBuild& InBuild);

	UFUNCTION(BlueprintPure, Category = "CourtLife") const FMyPlayerBuild& GetBuild() const { return Build; }
	UFUNCTION(BlueprintPure, Category = "CourtLife") ACLBasketball* GetBall() const { return Ball; }
	UFUNCTION(BlueprintPure, Category = "CourtLife") UCLShotComponent* GetShot() const { return Shot; }
	UFUNCTION(BlueprintPure, Category = "CourtLife") UCLDribbleComponent* GetDribble() const { return Dribble; }

	void OnShotStarted();

protected:
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly) TObjectPtr<USpringArmComponent> CameraBoom;
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly) TObjectPtr<UCameraComponent> Camera;
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly) TObjectPtr<UCLShotComponent> Shot;
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly) TObjectPtr<UCLDribbleComponent> Dribble;
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly) TObjectPtr<UCLCustomizationComponent> Customization;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "CourtLife") FMyPlayerBuild Build;
	UPROPERTY(EditAnywhere, Category = "CourtLife|Content") TObjectPtr<UCLAnimSet> AnimSet;
	UPROPERTY(EditAnywhere, Category = "CourtLife|Content") TObjectPtr<UCLCosmeticsCatalog> Catalog;
	UPROPERTY(EditAnywhere, Category = "CourtLife|Content") TSubclassOf<ACLBasketball> BallClass;
	/** Prop bone animated in dribble/shot clips; falls back to the hand sockets. */
	UPROPERTY(EditAnywhere, Category = "CourtLife|Content") FName BallBone = TEXT("ball_prop");
	UPROPERTY(EditAnywhere, Category = "CourtLife|Content") FName RightHandSocket = TEXT("hand_r_ball");
	UPROPERTY(EditAnywhere, Category = "CourtLife|Content") FName LeftHandSocket = TEXT("hand_l_ball");

	UPROPERTY(EditAnywhere, Category = "CourtLife|Input") TObjectPtr<UInputMappingContext> MappingContext;
	UPROPERTY(EditAnywhere, Category = "CourtLife|Input") TObjectPtr<UInputAction> MoveAction;
	UPROPERTY(EditAnywhere, Category = "CourtLife|Input") TObjectPtr<UInputAction> SprintAction;
	UPROPERTY(EditAnywhere, Category = "CourtLife|Input") TObjectPtr<UInputAction> ShootAction;
	/** One action per combo slot (0..7). On gamepad map these to the right stick / face buttons. */
	UPROPERTY(EditAnywhere, Category = "CourtLife|Input") TArray<TObjectPtr<UInputAction>> ComboActions;

private:
	void Move(const FInputActionValue& Value);
	void SprintStart(const FInputActionValue& Value);
	void SprintStop(const FInputActionValue& Value);
	void ShootPressed(const FInputActionValue& Value);
	void ShootReleased(const FInputActionValue& Value);
	void ComboPressed(int32 Slot);
	void AttachBallToHand();
	float BaseWalkSpeed() const;

	UPROPERTY() TObjectPtr<ACLBasketball> Ball;
	bool bSprinting = false;
};
